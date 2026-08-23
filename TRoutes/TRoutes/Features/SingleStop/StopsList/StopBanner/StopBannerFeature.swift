//
//  StopBannerFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//
import ComposableArchitecture
import CoreLocation
import Foundation
import SwiftUI

@Reducer
struct StopBannerFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        struct ID: Equatable, Hashable, Sendable {
            let stationId: String
            let routeId: String
            let lockedDirectionId: Int?

            init(target: BannerTarget) {
                self.stationId = target.stationId
                self.routeId = target.routeId
                self.lockedDirectionId = target.lockedDirectionId
            }
        }

        var target: BannerTarget
        var id: ID { ID(target: target) }
        var activeDirectionId: Int
        var isVisible: Bool = false
        var predictionSnapshots: [Int: StopPredictionSnapshot] = [:]
        var fetchingDirections: Set<Int> = []
        var lastFetchAttemptDates: [Int: Date] = [:]
        var stopCoordinates: CLLocationCoordinate2D?
        var userCoordinates: CLLocationCoordinate2D?
        @Shared(.displayUnits) var displayUnits = DisplayUnits.imperial.rawValue

        var predictions: [TransitPrediction] {
            predictionSnapshots[activeDirectionId]?.predictions ?? []
        }

        var isFetching: Bool {
            fetchingDirections.contains(activeDirectionId)
        }

        var routePresentation: RoutePresentation {
            RoutePresentation(routeId: target.routeId, transitType: target.transitType)
        }

        var liveActivityRequest: StopLiveActivityRequest {
            let destination: String
            if target.directionDestinations.indices.contains(activeDirectionId),
               !target.directionDestinations[activeDirectionId].isEmpty {
                destination = target.directionDestinations[activeDirectionId]
            } else {
                destination = activeDirectionId == 0 ? "Outbound" : "Inbound"
            }

            return StopLiveActivityRequest(
                key: StopPredictionKey(
                    stationId: target.stationId,
                    routeId: target.routeId,
                    directionId: activeDirectionId
                ),
                stopName: target.stopName,
                routePresentation: routePresentation,
                destination: destination,
                transitType: target.transitType,
                initialPredictions: predictions.map(\.display)
            )
        }

        var distance: CLLocationDistance? {
            guard let stopCoordinates, let userCoordinates else { return nil }
            return CLLocation(
                latitude: stopCoordinates.latitude,
                longitude: stopCoordinates.longitude
            ).distance(from: CLLocation(
                latitude: userCoordinates.latitude,
                longitude: userCoordinates.longitude
            ))
        }

        var formattedDistance: String? {
            guard let distance else { return nil }

            if displayUnits == DisplayUnits.metric.rawValue {
                if distance >= 1_000 {
                    return "\((distance / 1_000).formatted(.number.precision(.fractionLength(0...1)))) km"
                }
                return "\(distance.formatted(.number.precision(.fractionLength(0)))) m"
            }

            let feet = Measurement(value: distance, unit: UnitLength.meters)
                .converted(to: .feet)
                .value
            if feet >= 5_280 {
                return "\((feet / 5_280).formatted(.number.precision(.fractionLength(0...1)))) mi"
            }
            return "\(feet.formatted(.number.precision(.fractionLength(0)))) ft"
        }
        
        init(target: BannerTarget) {
            self.target = target
            if let lockedId = target.lockedDirectionId {
                self.activeDirectionId = lockedId
            } else {
                if target.directionDestinations.count > 1, 
                   target.directionDestinations[0].isEmpty, 
                   !target.directionDestinations[1].isEmpty {
                    self.activeDirectionId = 1
                } else {
                    self.activeDirectionId = 0
                }
            }
        }
        
        var isSwipeable: Bool {
            if target.isDirectionLocked { return false }
            if target.directionDestinations.count < 2 { return false }
            return !target.directionDestinations[0].isEmpty && !target.directionDestinations[1].isEmpty
        }
        
        var transitColor: SwiftUI.Color {
            if target.routeId.hasPrefix("SL") {
                return SwiftUI.Color(hex: "#7C878E")
            }
            return target.transitType.color
        }
        
        var transitForegroundColor: SwiftUI.Color {
            transitColor.isLightBackground ? .black : .white
        }
        
        var isSaved: Bool = false
        var pinnedDirections: Set<Int> = []
        
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case fetchPredictions
        case predictionsResponse(StopPredictionKey, StopPredictionSnapshot)
        case predictionsFailed(StopPredictionKey, Date)
        case directionSelected(Int)
        case liveActivityTapped
        case saveTapped
        case pinTapped
        case toggleSavedResponse(Result<Bool, DatabaseError>)
        case togglePinnedResponse(Result<Bool, DatabaseError>)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        
        enum Alert: Equatable {}
        
        enum Delegate: Equatable {
            case didChangeSaveStatus
            case didChangePinnedStatus
            case liveActivityRequested(StopLiveActivityRequest)
        }
    }

    @Dependency(\.databaseClient) var databaseClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isVisible = true
                return .send(.fetchPredictions)
                
            case .onDisappear:
                state.isVisible = false
                return .none
                
            case let .directionSelected(directionId):
                guard state.isSwipeable,
                      directionId != state.activeDirectionId,
                      state.target.directionDestinations.indices.contains(directionId),
                      !state.target.directionDestinations[directionId].isEmpty
                else { return .none }
                state.activeDirectionId = directionId
                return .send(.fetchPredictions)

            case .liveActivityTapped:
                return .send(.delegate(.liveActivityRequested(state.liveActivityRequest)))
                
            case .fetchPredictions:
                guard state.isVisible else { return .none }
                let now = Date()
                let key = StopPredictionKey(
                    stationId: state.target.stationId,
                    routeId: state.target.routeId,
                    directionId: state.activeDirectionId
                )
                if let snapshot = state.predictionSnapshots[key.directionId],
                   snapshot.isFresh(at: now, maxAge: 15) {
                    return .none
                }
                if let lastAttemptDate = state.lastFetchAttemptDates[key.directionId],
                   now.timeIntervalSince(lastAttemptDate) < 15 {
                    return .none
                }
                guard !state.fetchingDirections.contains(key.directionId) else { return .none }
                state.fetchingDirections.insert(key.directionId)
                state.lastFetchAttemptDates[key.directionId] = now

                return .run { send in
                    do {
                        let snapshot = try await StopPredictionCache.shared.predictions(for: key)
                        await send(.predictionsResponse(key, snapshot))
                    } catch {
                        await send(.predictionsFailed(key, Date()))
                    }
                }
                
            case let .predictionsResponse(key, snapshot):
                state.fetchingDirections.remove(key.directionId)
                state.lastFetchAttemptDates[key.directionId] = snapshot.fetchedAt
                state.predictionSnapshots[key.directionId] = snapshot
                return .none

            case let .predictionsFailed(key, failedAt):
                state.fetchingDirections.remove(key.directionId)
                state.lastFetchAttemptDates[key.directionId] = failedAt
                return .none
                
            case .saveTapped:
                let target = state.target
                let isSaved = state.isSaved
                let stop = SingleStop(
                    id: target.id,
                    stationId: target.stationId,
                    platformId: target.platformId,
                    routeId: target.routeId,
                    stopName: target.stopName,
                    transitType: target.transitType,
                    directionDestinations: target.directionDestinations
                )
                return .run { send in
                    do {
                        if isSaved {
                            try await databaseClient.removeSavedStop(stop)
                            await send(.toggleSavedResponse(.success(false)))
                        } else {
                            try await databaseClient.addSavedStop(stop)
                            await send(.toggleSavedResponse(.success(true)))
                        }
                    } catch let error as DatabaseError {
                        await send(.toggleSavedResponse(.failure(error)))
                    } catch {
                        // ignore unknown errors
                    }
                }
                
            case .pinTapped:
                let target = state.target
                let directionId = state.activeDirectionId
                let isPinned = state.pinnedDirections.contains(directionId)
                let pinnedStop = PinnedStop(
                    id: UUID(), // Pinned stops get unique IDs per pin
                    stationId: target.stationId,
                    platformId: target.platformId,
                    routeId: target.routeId,
                    directionId: directionId,
                    stopName: target.stopName,
                    transitType: target.transitType,
                    directionDestinations: target.directionDestinations
                )
                
                return .run { send in
                    do {
                        if isPinned {
                            try await databaseClient.removePinnedStop(pinnedStop)
                            await send(.togglePinnedResponse(.success(false)))
                        } else {
                            try await databaseClient.addPinnedStop(pinnedStop)
                            await send(.togglePinnedResponse(.success(true)))
                        }
                    } catch let error as DatabaseError {
                        await send(.togglePinnedResponse(.failure(error)))
                    } catch {
                        // ignore unknown errors
                    }
                }
                
            case .toggleSavedResponse(.success(let saved)):
                state.isSaved = saved
                return .send(.delegate(.didChangeSaveStatus))
                
            case .toggleSavedResponse(.failure(let error)):
                if error == .savedLimitReached {
                    state.alert = AlertState {
                        TextState("Saved Limit Reached")
                    } message: {
                        TextState("You can only have up to 20 saved stops. Please remove one before adding another.")
                    }
                }
                return .none
                
            case .togglePinnedResponse(.success(let pinned)):
                if pinned {
                    state.pinnedDirections.insert(state.activeDirectionId)
                } else {
                    state.pinnedDirections.remove(state.activeDirectionId)
                }
                return .send(.delegate(.didChangePinnedStatus))
                
            case .togglePinnedResponse(.failure(let error)):
                if error == .pinnedLimitReached {
                    state.alert = AlertState {
                        TextState("Pinned Limit Reached")
                    } message: {
                        TextState("You can only have up to 3 pinned stops. Please remove one before pinning another.")
                    }
                }
                return .none
                
            case .alert:
                return .none
                
            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

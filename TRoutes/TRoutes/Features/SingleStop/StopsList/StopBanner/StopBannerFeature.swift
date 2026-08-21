//
//  StopBannerFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct StopBannerFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var target: BannerTarget
        var id: UUID { target.id }
        var activeDirectionId: Int
        var isVisible: Bool = false
        var predictions: [TransitPrediction] = []
        var isFetching: Bool = false
        
        init(target: BannerTarget) {
            self.target = target
            // Pinned stops lock to their direction; saved stops start at 0
            self.activeDirectionId = target.lockedDirectionId ?? 0
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
        case predictionsResponse(Result<[TransitPrediction], Never>)
        case switchDirectionTapped
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
        }
    }

    @Dependency(\.mbtaClient) var mbtaClient
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
                
            case .switchDirectionTapped:
                // Only allow direction switching for non-pinned (saved) stops
                guard !state.target.isDirectionLocked else { return .none }
                state.activeDirectionId = state.activeDirectionId == 0 ? 1 : 0
                state.predictions = []
                return .send(.fetchPredictions)
                
            case .fetchPredictions:
                guard state.isVisible else { return .none }
                state.isFetching = true
                
                let request = BannerPredictionRequest(
                    predictionRouteId: state.target.routeId,
                    predictionStopIds: [state.target.stationId],
                    predictionDirectionId: state.activeDirectionId
                )
                let routeIds = [state.target.routeId]
                return .run { send in
                    do {
                        let predictions = try await mbtaClient.fetchTransitTimes(request, routeIds, .predictionRefresh)
                        await send(.predictionsResponse(.success(predictions)))
                    } catch {
                        await send(.predictionsResponse(.success([])))
                    }
                }
                
            case let .predictionsResponse(.success(predictions)):
                state.isFetching = false
                state.predictions = predictions
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

/// Lightweight PredictionTarget for banner API calls.
/// Constructed from the banner's target + active direction state.
private struct BannerPredictionRequest: PredictionTarget {
    var predictionRouteId: String
    var predictionStopIds: [String]
    var predictionDirectionId: Int
}

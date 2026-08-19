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
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case fetchPredictions
        case predictionsResponse(Result<[TransitPrediction], Never>)
        case switchDirectionTapped
    }

    @Dependency(\.mbtaClient) var mbtaClient

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
            }
        }
    }
}

/// Lightweight PredictionTarget for banner API calls.
/// Constructed from the banner's target + active direction state.
private struct BannerPredictionRequest: PredictionTarget {
    var predictionRouteId: String
    var predictionStopIds: [String]
    var predictionDirectionId: Int
}

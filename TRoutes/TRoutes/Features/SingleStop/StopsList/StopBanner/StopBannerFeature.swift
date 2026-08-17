//
//  StopBannerFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct StopBannerFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var target: SingleStop
        var id: UUID { target.id }        
        var isVisible: Bool = false
        var predictions: [TransitPrediction] = []
        var isFetching: Bool = false
        
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
                // Flip direction 0 <-> 1
                state.target.directionId = state.target.directionId == 0 ? 1 : 0
                state.predictions = []
                return .send(.fetchPredictions)
                
            case .fetchPredictions:
                guard state.isVisible else { return .none }
                state.isFetching = true
                
                let target = state.target
                return .run { send in
                    do {
                        let predictions = try await mbtaClient.fetchTransitTimes(target, [target.routeId], .predictionRefresh)
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

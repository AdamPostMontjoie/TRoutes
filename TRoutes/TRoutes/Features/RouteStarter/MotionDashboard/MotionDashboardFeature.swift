//
//  MotionDashboardFeature.swift
//  TRoutes
//

import ComposableArchitecture
import CoreMotion

@Reducer
struct MotionDashboardFeature {
    @ObservableState
    struct State: Equatable {
        var isListening = false
        var currentActivity: String = "Unknown"
        var confidence: String = "Low"
    }

    enum Action: Equatable {
        case toggleListening
        case activityUpdated(String, String) // activity name, confidence
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleListening:
                state.isListening.toggle()
                if state.isListening {
                    return .run { send in
                        await MotionManager.shared.startEvents()
                        let stream = await MotionManager.shared.makeEventStream()
                        for await event in stream {
                            await send(.activityUpdated(event.state.rawValue, event.confidence))
                        }
                    }
                    .cancellable(id: "MotionStream")
                } else {
                    return .run { _ in
                        await MotionManager.shared.stopEvents()
                    }
                    .merge(with: .cancel(id: "MotionStream"))
                }
                
            case let .activityUpdated(activityName, confidenceName):
                state.currentActivity = activityName
                state.confidence = confidenceName
                return .none
            }
        }
    }
}

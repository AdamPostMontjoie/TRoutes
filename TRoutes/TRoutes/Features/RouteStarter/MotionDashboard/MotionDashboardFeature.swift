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
        var currentState: String = "—"
        var magnitude: String = "—"
        var variance: String = "—"
        var joltDuration: String = "—"
        var isJoltDetected: Bool = false
    }

    enum Action: Equatable {
        case toggleListening
        case motionEventReceived(state: String, magnitude: Double, variance: Double, joltDuration: Double, isJoltDetected: Bool)
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
                            await send(.motionEventReceived(
                                state: event.state.rawValue,
                                magnitude: event.magnitude,
                                variance: event.variance,
                                joltDuration: event.joltDuration,
                                isJoltDetected: event.isJoltDetected
                            ))
                        }
                    }
                    .cancellable(id: "MotionStream")
                } else {
                    return .run { _ in
                        await MotionManager.shared.stopEvents()
                    }
                    .merge(with: .cancel(id: "MotionStream"))
                }
                
            case let .motionEventReceived(motionState, magnitude, variance, joltDuration, isJoltDetected):
                state.currentState = motionState
                state.magnitude = String(format: "%.4f G", magnitude)
                state.variance = String(format: "%.6f", variance)
                state.joltDuration = joltDuration > 0 ? String(format: "%.1f s", joltDuration) : "—"
                state.isJoltDetected = isJoltDetected
                return .none
            }
        }
    }
}

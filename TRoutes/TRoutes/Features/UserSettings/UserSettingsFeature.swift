//
//  UserSettingsFeature.swift
//  TRoutes
//
//  Created by Adam Post on 6/14/26.
//
import ComposableArchitecture

@Reducer
struct UserSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var isDebugAvailable = DebugAvailability.current
        @Shared(.isDebugEnabled) var isDebugEnabled = true
        @Shared(.isMotionEventsEnabled) var isMotionEventsEnabled = true
        var apiKeyInput: String = ""

        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
    }

    enum Action: Equatable {
        case debugEnabledChanged(Bool)
        case motionEventsEnabledChanged(Bool)
        case apiKeyInputChanged(String)
        case apiKeySubmitted
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .debugEnabledChanged(enabled):
                guard state.isDebugAvailable else { return .none }
                state.$isDebugEnabled.withLock {
                    $0 = enabled
                }
                return .none
            case let .motionEventsEnabledChanged(enabled):
                guard state.isDebugAvailable else { return .none }
                state.$isMotionEventsEnabled.withLock {
                    $0 = enabled
                }
                return .none
            case let .apiKeyInputChanged(value):
                state.apiKeyInput = value
                return .none
            case .apiKeySubmitted:
                // TODO: Validate key via MBTAClient and set hasValidApiKey
                return .none
            }
        }
    }
}


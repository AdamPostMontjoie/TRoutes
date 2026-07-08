//
//  UserSettingsFeature.swift
//  MBTAFlow
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

        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
    }

    enum Action: Equatable {
        case debugEnabledChanged(Bool)
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
            }
        }
    }
}

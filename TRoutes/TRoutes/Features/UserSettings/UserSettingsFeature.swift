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
        @Shared(.mbtaApiKey) var mbtaApiKey = ""
        @Shared(.hasValidApiKey) var hasValidApiKey = false
        @Shared(.displayUnits) var displayUnits = DisplayUnits.imperial.rawValue
        var apiKeyInput: String = ""
        var isVerifyingKey = false
        var keyVerificationFailed = false

        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
    }

    enum Action: Equatable {
        case debugEnabledChanged(Bool)
        case motionEventsEnabledChanged(Bool)
        case displayUnitsChanged(String)
        case apiKeyInputChanged(String)
        case apiKeySubmitted
        case removeKeyButtonTapped
        case verificationResult(Result<Bool, Never>)
    }
    
    @Dependency(\.mbtaClient) var mbtaClient
    
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
            case let .displayUnitsChanged(units):
                guard DisplayUnits(rawValue: units) != nil else { return .none }
                state.$displayUnits.withLock { $0 = units }
                return .none
            case let .apiKeyInputChanged(value):
                state.apiKeyInput = value
                state.keyVerificationFailed = false
                return .none
            case .removeKeyButtonTapped:
                state.$hasValidApiKey.withLock { $0 = false }
                state.$mbtaApiKey.withLock { $0 = "" }
                state.apiKeyInput = ""
                return .none
            case .apiKeySubmitted:
                guard !state.apiKeyInput.isEmpty else { return .none }
                state.isVerifyingKey = true
                state.keyVerificationFailed = false
                let keyToTest = state.apiKeyInput
                let verifyAPIKey = mbtaClient.verifyAPIKey
                return .run { send in
                    do {
                        let isValid = try await verifyAPIKey(keyToTest)
                        await send(.verificationResult(.success(isValid)))
                    } catch {
                        await send(.verificationResult(.success(false)))
                    }
                }
            case let .verificationResult(.success(isValid)):
                state.isVerifyingKey = false
                if isValid {
                    state.$mbtaApiKey.withLock { $0 = state.apiKeyInput }
                    state.$hasValidApiKey.withLock { $0 = true }
                    state.apiKeyInput = ""
                } else {
                    state.keyVerificationFailed = true
                }
                return .none
            }
        }
    }
}


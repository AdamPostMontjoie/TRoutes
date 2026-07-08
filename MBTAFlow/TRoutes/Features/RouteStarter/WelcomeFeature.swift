//
//  WelcomeFeature.swift
//  TRoutes
//
//  Created by Adam Post on 7/8/26.
//

import ComposableArchitecture

@Reducer
struct WelcomeFeature {
    @ObservableState
    struct State: Equatable {
        var isDebugAvailable = DebugAvailability.current
        @Shared(.isDebugEnabled) var isDebugEnabled = true
        @Shared(.hasOnboarded) var hasOnboarded = false
        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
    }

    enum Action: Equatable {
        case continueButtonClicked
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case continueTapped
        }
    }
    
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .continueButtonClicked:
                state.hasOnboarded = true
                return .run { send in
                    await send(.delegate(.continueTapped))
                    await dismiss()
                }
            case .delegate:
                return .none
            }
        }
    }
}

extension SharedReaderKey where Self == AppStorageKey<Bool> {
    static var hasOnboarded: Self {
        appStorage("hasOnboarded")
    }
}

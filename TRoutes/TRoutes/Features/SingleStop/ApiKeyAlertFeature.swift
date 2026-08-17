//
//  ApiKeyAlertFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture

@Reducer
struct ApiKeyAlertFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {
        case dismissButtonTapped
        case delegate(Delegate)
        enum Delegate: Equatable {
            case dismiss
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .dismissButtonTapped:
                return .send(.delegate(.dismiss))
            case .delegate:
                return .none
            }
        }
    }
}

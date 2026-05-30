//
//  CreateStepFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct CreateRouteFeature {
    @ObservableState
    struct State: Equatable {
        var routeName = ""
        var startingStop = ""
        var endingStop = ""
        var departureTime = ""
    }

    enum Action: Equatable {
        case createButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .createButtonTapped:
                return .none
            }
        }
    }
}

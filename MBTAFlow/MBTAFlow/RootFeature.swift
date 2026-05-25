//
//  RootFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct RootFeature {
    @ObservableState
    struct State: Equatable {
        var starter = RouteStarterFeature.State()
        var setter = RouteSetterFeature.State()
    }
    
    enum Tab { case starter, setter }
    
    enum Action {
        case starterTab(RouteStarterFeature.Action)
        case setterTab(RouteSetterFeature.Action)
    }
    
    var body: some ReducerOf<Self> {
        Scope(state: \.starter, action: \.starterTab) {
            RouteStarterFeature()
        }
        Scope(state: \.setter, action: \.setterTab) {
            RouteSetterFeature()
        }
        Reduce { state, action in
            return .none
        }
    }
}

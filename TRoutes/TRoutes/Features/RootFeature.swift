//
//  RootFeature.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct RootFeature {
    @ObservableState
    struct State: Equatable {
        var application = ApplicationState()
        var starter = RouteStarterFeature.State()
    }
    
    enum Action {
       case starterTab(RouteStarterFeature.Action)
        
    }
    
    var body: some ReducerOf<Self> {
        Scope(state: \.starter, action: \.starterTab) {
          RouteStarterFeature()
       }
        Reduce { state, action in
            switch action{
            case .starterTab:
                return .none
            }
        }
    }
}

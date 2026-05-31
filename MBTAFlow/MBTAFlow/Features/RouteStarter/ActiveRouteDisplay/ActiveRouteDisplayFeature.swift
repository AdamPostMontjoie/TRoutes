//
//  ActiveRouteDisplayFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct ActiveRouteDisplayFeature {
    @ObservableState
    struct State: Equatable {
        var route:RouteStruct? //this will be edited live, active reflection of where the user is on the route
    }
    
    //no other actions needed, this is just a reflection
    enum Action: Equatable {
        case cancelButtonTapped
        case delegate(Delegate)
        enum Delegate:Equatable {
            case cancelRoute //kills the active route
        }
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cancelButtonTapped://maybe add intermediate alert to stop accidental cancelation
                return .send(.delegate(.cancelRoute))
            case .delegate:
                return .none
            }
        }
    }
}

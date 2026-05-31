//
//  ActiveRouteFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct ActiveRouteFeature {
    @ObservableState
    struct State: Equatable {
        var title = "Active Route"
        var subtitle = "No route started"
    }
    
    enum Action: Equatable {
        case cancelButtonTapped
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cancelButtonTapped:
                return .none
            }
        }
    }
}

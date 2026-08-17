//
//  SingleStopFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture

@Reducer
struct SingleStopFeature {
    @ObservableState
    struct State: Equatable {
       
    }
    
    enum Action {
       
        
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            return .none
        }
    }
}

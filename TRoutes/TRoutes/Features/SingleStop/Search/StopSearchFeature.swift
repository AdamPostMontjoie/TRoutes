//
//  StopSearchFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import ComposableArchitecture
import Foundation

@Reducer
struct StopSearchFeature {
    @ObservableState
    struct State: Equatable {
        var query: String = ""
    }

    enum Action: Equatable {
        case queryChanged(String)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .queryChanged(query):
                state.query = query
                return .none
            }
        }
    }
}

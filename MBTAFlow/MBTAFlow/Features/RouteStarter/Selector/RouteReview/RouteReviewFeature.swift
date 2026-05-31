//
//  RouteReviewFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture

@Reducer
struct RouteReviewFeature {
    @ObservableState
    struct State: Equatable {
        var route: RouteStruct
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

//
//  DebugDashboardFeature.swift
//  TRoutes
//
//  Created by Adam Post on 7/7/26.
//

import ComposableArchitecture

@Reducer
struct DebugDashboardFeature {
    @ObservableState
    struct State: Equatable {
        var journey: JourneyState?

        var title: String {
            journey?.route.name ?? "No active journey"
        }

        var progressText: String {
            guard let journey else { return "No journey" }
            return "Stop \(journey.stopIndex + 1)/\(journey.stopOrder.count) • Leg \(journey.legIndex + 1)/\(journey.legOrder.count)"
        }
    }
    
    enum Action:Equatable {
       
        
    }
    
    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

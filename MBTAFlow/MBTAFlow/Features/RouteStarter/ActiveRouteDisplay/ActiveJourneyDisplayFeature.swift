//
//  ActiveJourneyDisplayFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct ActiveJourneyDisplayFeature {
    @ObservableState
    struct State: Equatable {
        //direct reflection of activeJourney in RouteStartFeature
        var journey: JourneyState?
    }

    enum Action: Equatable {
        case cancelButtonTapped
        case delegate(Delegate)
        enum Delegate:Equatable {
            case cancelRoute
            case atStop
            case nextStop
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

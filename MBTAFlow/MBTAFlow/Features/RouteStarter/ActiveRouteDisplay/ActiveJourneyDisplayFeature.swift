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
        
        var shouldShowStopActionButton: Bool {
            journey?.currentStop?.stopType != .finalStop || journey?.movementStatus == .enRoute
        }
        
        var movementIconName: String {
            switch journey?.movementStatus {
            case .enRoute, .none:
                return "mappin.circle.fill"
            case .atStop:
                return "arrow.right.circle.fill"
            }
        }
    }

    enum Action: Equatable {
        case cancelButtonTapped
        case nextStopButtonTapped
        case atStopButtonTapped
        case delegate(Delegate)
        enum Delegate:Equatable {
            case cancelRoute
            case manualAtStop
            case manualNextStop
        }
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cancelButtonTapped://maybe add intermediate alert to stop accidental cancelation
                return .send(.delegate(.cancelRoute))
            case .atStopButtonTapped:
                return .send(.delegate(.manualAtStop))
            case .nextStopButtonTapped:
                return .send(.delegate(.manualNextStop))
            case .delegate:
                return .none
            }
        }
    }
}

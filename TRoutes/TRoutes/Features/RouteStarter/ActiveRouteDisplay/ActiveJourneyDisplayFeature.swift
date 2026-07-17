//
//  ActiveJourneyDisplayFeature.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ActiveJourneyDisplayFeature {
    @ObservableState
    struct State: Equatable {
        //direct reflection of activeJourney in RouteStartFeature
        var journey: JourneyState?
        
        var isDebugAvailable = DebugAvailability.current
        @Shared(.isDebugEnabled) var isDebugEnabled = true
        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
        
        var shouldShowStopActionButton: Bool {
            if journey?.pendingDepartureConfirmation == true {
                return false
            }
            if isDebugActive { return true }
            guard let journey = journey else { return false }
            if journey.movementStatus == .enRoute && journey.currentStop?.stopType == .boardingStop && journey.monitoringMode == .underground  {return true}
            
            return false
        }
        
        var movementIconName: String {
            switch journey?.movementStatus {
            case .enRoute, .none:
                return "mappin.circle.fill"
            case .atStop:
                return "arrow.right.circle.fill"
            }
        }
        
        var shouldShowRefreshButton: Bool {
            return isDebugActive
        }
        
        var presentation: JourneyPresentationState {
            JourneyPresentationState(journey: journey)
        }
    }

    enum Action: Equatable {
        case cancelButtonTapped
        case nextStopButtonTapped
        case atStopButtonTapped
        case refreshButtonTapped
        case confirmedBoardedTapped
        case confirmedMissedTapped
        case delegate(Delegate)
        enum Delegate:Equatable {
            case cancelRoute
            case manualAtStop
            case manualNextStop
            case refreshTimes
            case confirmedBoarded
            case confirmedMissed
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
            case .refreshButtonTapped:
                return .send(.delegate(.refreshTimes))
            case .confirmedBoardedTapped:
                return .send(.delegate(.confirmedBoarded))
            case .confirmedMissedTapped:
                return .send(.delegate(.confirmedMissed))
            case .delegate:
                return .none
            }
        }
    }
}

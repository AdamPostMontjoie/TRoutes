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
            if journey?.pendingDepartureConfirmation == true {
                return false
            }
            return journey?.currentStop?.stopType != .finalStop || journey?.movementStatus == .enRoute
        }
        
        var movementIconName: String {
            switch journey?.movementStatus {
            case .enRoute, .none:
                return "mappin.circle.fill"
            case .atStop:
                return "arrow.right.circle.fill"
            }
        }
        
        var currentDisplayPredictionLoadingState: PredictionLoadingState? {
            return journey?.predictionState?.loadingState
        }
        
        var currentPredictionType: PredictionTargetType? {
            return journey?.predictionState?.predictedStopType
        }
        
        var shouldShowRefreshButton: Bool {
            switch currentDisplayPredictionLoadingState {
            case .loaded, .unavailable,.loading:
                return true
            case .none:
                return false
            }
        }
        
        var stopDisplayText: String {
            guard let journey = journey,
                  let currentStop = journey.currentStop,
                  let currentLeg = journey.currentLeg,
                  let legFinalStop = currentLeg.stops.last,
                  let finalStop = journey.stopOrder.last else {
                return ""
            }
            
            let totalStops = journey.stopOrder.count
            let currentIndex = journey.stopIndex
            
            //boarding
            if currentIndex == 0 && journey.movementStatus == .atStop {
                return "At: \(currentStop.stopName)"
            }
            
            //at final
            if currentIndex == totalStops - 1 && journey.movementStatus == .atStop {
                return "Arrived at \(finalStop.stopName)"
            }
            
            let legTotalStops = currentLeg.stops.count
            let legCurrentIndex = currentStop.legStopIndex
            
            // Calculate stops remaining in the current leg
            let stopsRemainingInLeg = journey.movementStatus == .atStop
                ? (legTotalStops - 1 - legCurrentIndex)
                : (legTotalStops - legCurrentIndex)
                
            let isTransferLeg = journey.legIndex < journey.legOrder.count - 1
            
            //transfer at next stop
            if isTransferLeg && stopsRemainingInLeg == 1 && journey.movementStatus == .atStop {
                return "Transfer at next stop: \(legFinalStop.stopName)"
            }
            
            //en route to transfer stop
            if isTransferLeg && stopsRemainingInLeg == 1 && journey.movementStatus == .enRoute {
                return "Approaching: \(currentStop.stopName) (Transfer)"
            }
            
            //one stop remaining in journey (.final)
            if !isTransferLeg && stopsRemainingInLeg == 1 && journey.movementStatus == .atStop {
                return "Get off at next stop: \(legFinalStop.stopName)"
            }
            
            //on way to last stop (.final)
            if !isTransferLeg && stopsRemainingInLeg == 1 && journey.movementStatus == .enRoute {
                return "Approaching: \(currentStop.stopName). This is your stop"
            }
            
            //intermediate stops
            let stopsText = stopsRemainingInLeg == 1 ? "1 stop" : "\(stopsRemainingInLeg) stops"
            let destinationName = isTransferLeg ? "\(legFinalStop.stopName) (Transfer)" : legFinalStop.stopName
            
            if journey.movementStatus == .atStop {
                return "At: \(currentStop.stopName) • \(stopsText) to \(destinationName)"
            } else {
                return "En Route to: \(currentStop.stopName) • \(stopsText) to \(destinationName)"
            }
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

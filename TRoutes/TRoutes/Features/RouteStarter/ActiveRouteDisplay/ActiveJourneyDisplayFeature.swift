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
        
        var currentLocationContext: String {
            guard let journey = journey, let currentStop = journey.currentStop else { return "" }
            
            if journey.stopIndex == 0 {
                if journey.movementStatus == .atStop {
                    return "At: \(currentStop.stopName)"
                } else {
                    return "Go to: \(currentStop.stopName)"
                }
            } else {
                if journey.movementStatus == .atStop {
                    return "At: \(currentStop.stopName)"
                } else {
                    return "Next Stop: \(currentStop.stopName)"
                }
            }
        }
        
        var destinationContext: String? {
            guard let journey = journey,
                  let currentLeg = journey.currentLeg,
                  journey.stopIndex != 0,
                  let legFinalStop = currentLeg.stops.last else { return nil }
            
            let legTotalStops = currentLeg.stops.count
            let legCurrentIndex = journey.currentStop?.legStopIndex ?? 0
            
            if journey.isEndOfJourney {
                return "Arrived at \(journey.stopOrder.last?.stopName ?? "")"
            }
            
            let stopsRemainingInLeg = journey.movementStatus == .atStop
                ? max(0, legTotalStops - 1 - legCurrentIndex)
                : max(0, legTotalStops - legCurrentIndex)
                
            let stopsText = stopsRemainingInLeg == 1 ? "1 stop" : "\(stopsRemainingInLeg) stops"
            let isTransferLeg = journey.legIndex < journey.legOrder.count - 1
            
            if isTransferLeg {
                if stopsRemainingInLeg == 1 && journey.movementStatus == .atStop {
                    return "Last stop before \(legFinalStop.stopName)"
                }
                return "\(stopsText) to \(legFinalStop.stopName)"
            } else {
                if stopsRemainingInLeg == 1 && journey.movementStatus == .enRoute {
                    return "Get off at next stop"
                }
                return "\(stopsText) to \(legFinalStop.stopName)"
            }
        }
        
        var transferContext: String? {
            guard let journey = journey else { return nil }
            let isTransferLeg = journey.legIndex < journey.legOrder.count - 1
            guard isTransferLeg, let currentLeg = journey.currentLeg, let nextLeg = journey.legOrder.dropFirst(journey.legIndex + 1).first else { return nil }
            
            let legTotalStops = currentLeg.stops.count
            let legCurrentIndex = journey.currentStop?.legStopIndex ?? 0
            let stopsRemainingInLeg = journey.movementStatus == .atStop
                ? max(0, legTotalStops - 1 - legCurrentIndex)
                : max(0, legTotalStops - legCurrentIndex)
                
            let nextLineName = nextLeg.transitType.rawValue
            
            if stopsRemainingInLeg == 1 && journey.movementStatus == .atStop {
                return "Transfer to \(nextLineName) at \(currentLeg.stops.last?.stopName ?? "next stop")"
            } else if stopsRemainingInLeg == 0 {
                return "Transfer to \(nextLineName)"
            }
            return nil
        }
        
        var currentTransitType: TransitType? {
            journey?.currentLeg?.transitType
        }
        
        var shortRouteName: String {
            guard let leg = journey?.currentLeg else { return "" }
            switch leg.transitType {
            case .redLine: return "RL"
            case .orangeLine: return "OL"
            case .blueLine: return "BL"
            case .greenLine:
                return "GL"
            case .mattapan: return "M"
            case .commuterRail: return "CR"
            case .bus:
                return leg.mbtaRouteId
            case .ferry:
                if leg.mbtaRouteId.hasPrefix("Boat-") {
                    return leg.mbtaRouteId.replacingOccurrences(of: "Boat-", with: "")
                }
                return leg.mbtaRouteId
            }
        }
        
        var routeDestination: String {
            guard let leg = journey?.currentLeg else { return "" }
            if let direction = leg.transitDirection {
                return direction.destination
            }
            return leg.stops.last?.stopName ?? ""
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

//
//  JourneyPresentationState.swift
//  TRoutes
//

import Foundation

struct JourneyPresentationState: Equatable, Codable {
    let shortRouteName: String
    let routeDestination: String
    let currentLocationContext: String
    let destinationContext: String?
    let transferContext: String?
    let currentTransitType: TransitType?
    let isEndOfJourney: Bool
    
    // Predictions
    let activePredictions: [JourneyAttributes.PredictionDisplay]
    let activePredictionLoadingState: PredictionLoadingState?
    
    // Transfer Leg Data
    let transferPredictions: [JourneyAttributes.PredictionDisplay]?
    let transferPredictionLoadingState: PredictionLoadingState?
    let nextLegTransitType: TransitType?
    
    init(journey: JourneyState?) {
        guard let journey = journey else {
            self.shortRouteName = ""
            self.routeDestination = ""
            self.currentLocationContext = ""
            self.destinationContext = nil
            self.transferContext = nil
            self.currentTransitType = nil
            self.isEndOfJourney = false
            self.activePredictions = []
            self.activePredictionLoadingState = nil
            self.transferPredictions = nil
            self.transferPredictionLoadingState = nil
            self.nextLegTransitType = nil
            return
        }
        
        // shortRouteName
        if let leg = journey.currentLeg {
            switch leg.transitType {
            case .redLine: self.shortRouteName = "RL"
            case .orangeLine: self.shortRouteName = "OL"
            case .blueLine: self.shortRouteName = "BL"
            case .greenLine: self.shortRouteName = "GL"
            case .mattapan: self.shortRouteName = "M"
            case .commuterRail: self.shortRouteName = "CR"
            case .bus: self.shortRouteName = leg.mbtaRouteId
            case .ferry:
                if leg.mbtaRouteId.hasPrefix("Boat-") {
                    self.shortRouteName = leg.mbtaRouteId.replacingOccurrences(of: "Boat-", with: "")
                } else {
                    self.shortRouteName = leg.mbtaRouteId
                }
            }
        } else {
            self.shortRouteName = ""
        }
        
        // routeDestination
        if let leg = journey.currentLeg {
            if let direction = leg.transitDirection {
                self.routeDestination = direction.destination
            } else {
                self.routeDestination = leg.stops.last?.stopName ?? ""
            }
        } else {
            self.routeDestination = ""
        }
        
        // currentLocationContext
        if let currentStop = journey.currentStop {
            if journey.stopIndex == 0 {
                if journey.movementStatus == .atStop {
                    self.currentLocationContext = "At: \(currentStop.stopName)"
                } else {
                    self.currentLocationContext = "Go to: \(currentStop.stopName)"
                }
            } else {
                if journey.movementStatus == .atStop {
                    self.currentLocationContext = "At: \(currentStop.stopName)"
                } else {
                    self.currentLocationContext = "Next Stop: \(currentStop.stopName)"
                }
            }
        } else {
            self.currentLocationContext = ""
        }
        
        // destinationContext
        self.isEndOfJourney = journey.isEndOfJourney
        if journey.isEndOfJourney {
            self.destinationContext = "Arrived at \(journey.stopOrder.last?.stopName ?? "")"
        } else if let currentLeg = journey.currentLeg, journey.stopIndex != 0, let legFinalStop = currentLeg.stops.last {
            let legTotalStops = currentLeg.stops.count
            let legCurrentIndex = journey.currentStop?.legStopIndex ?? 0
            
            // Includes destination in the count (industry standard)
            let stopsLeft = journey.movementStatus == .atStop
                ? max(0, legTotalStops - 1 - legCurrentIndex)
                : max(0, legTotalStops - legCurrentIndex)
                
            let isTransferLeg = journey.legIndex < journey.legOrder.count - 1
            
            if isTransferLeg {
                if stopsLeft <= 1 && journey.movementStatus == .atStop {
                    self.destinationContext = "Transfer at \(legFinalStop.stopName)"
                } else if stopsLeft == 1 && journey.movementStatus == .enRoute {
                    self.destinationContext = "Transfer at next stop"
                } else if stopsLeft == 0 {
                    self.destinationContext = nil
                } else {
                    let stopsText = stopsLeft == 1 ? "1 stop" : "\(stopsLeft) stops"
                    self.destinationContext = "\(stopsText) left"
                }
            } else {
                if stopsLeft == 1 && journey.movementStatus == .enRoute {
                    self.destinationContext = "Get off at next stop"
                } else if stopsLeft == 0 {
                    self.destinationContext = nil
                } else {
                    let stopsText = stopsLeft == 1 ? "1 stop" : "\(stopsLeft) stops"
                    self.destinationContext = "\(stopsText) left"
                }
            }
        } else {
            self.destinationContext = nil
        }
        
        // transferContext
        let isTransferLeg = journey.legIndex < journey.legOrder.count - 1
        if isTransferLeg, let currentLeg = journey.currentLeg, let nextLeg = journey.legOrder.dropFirst(journey.legIndex + 1).first {
            let legTotalStops = currentLeg.stops.count
            let legCurrentIndex = journey.currentStop?.legStopIndex ?? 0
            let stopsRemainingInLeg = journey.movementStatus == .atStop
                ? max(0, legTotalStops - 1 - legCurrentIndex)
                : max(0, legTotalStops - legCurrentIndex)
                
            let nextLineName = nextLeg.transitType.rawValue
            
            if stopsRemainingInLeg == 1 && journey.movementStatus == .atStop {
                self.transferContext = "Transfer to \(nextLineName) at \(currentLeg.stops.last?.stopName ?? "next stop")"
            } else if stopsRemainingInLeg == 0 {
                self.transferContext = "Transfer to \(nextLineName)"
            } else {
                self.transferContext = nil
            }
        } else {
            self.transferContext = nil
        }
        
        // currentTransitType
        self.currentTransitType = journey.currentLeg?.transitType
        
        // Predictions
        if let activePrediction = journey.activeLegPrediction {
            self.activePredictionLoadingState = activePrediction.loadingState
            switch activePrediction.loadingState {
            case let .loaded(_, times):
                self.activePredictions = zip(times, activePrediction.lastObservedPredictions).map {
                    JourneyAttributes.PredictionDisplay(time: $0.0, badge: $0.1.branchLabel)
                }
            case .loading:
                self.activePredictions = activePrediction.lastObservedPredictions.map {
                    JourneyAttributes.PredictionDisplay(time: $0.display, badge: $0.branchLabel)
                }
            case .unavailable:
                self.activePredictions = []
            }
        } else {
            self.activePredictionLoadingState = nil
            self.activePredictions = []
        }
        
        // Transfer Predictions and Styling
        if let transferPrediction = journey.transferLegPrediction {
            self.transferPredictionLoadingState = transferPrediction.loadingState
            switch transferPrediction.loadingState {
            case let .loaded(_, times):
                self.transferPredictions = zip(times, transferPrediction.lastObservedPredictions).map {
                    JourneyAttributes.PredictionDisplay(time: $0.0, badge: $0.1.branchLabel)
                }
            case .loading:
                self.transferPredictions = transferPrediction.lastObservedPredictions.map {
                    JourneyAttributes.PredictionDisplay(time: $0.display, badge: $0.branchLabel)
                }
            case .unavailable:
                self.transferPredictions = []
            }
        } else {
            self.transferPredictionLoadingState = nil
            self.transferPredictions = nil
        }
        
        // Next Leg
        let nextIndex = journey.legIndex + 1
        if nextIndex < journey.legOrder.count {
            self.nextLegTransitType = journey.legOrder[nextIndex].transitType
        } else {
            self.nextLegTransitType = nil
        }
    }
}

//
//  JourneyPresentationState.swift
//  TRoutes
//

import Foundation

struct JourneyPresentationState: Equatable, Codable {
    struct TimingStep: Equatable, Codable {
        let iconName: String
        let text: String
        let time: Date?
        let source: TimingSource?
        let badgeText: String?
        let transitType: TransitType?

        init(iconName: String, text: String, time: Date? = nil, source: TimingSource? = nil, badgeText: String? = nil, transitType: TransitType? = nil) {
            self.iconName = iconName
            self.text = text
            self.time = time
            self.source = source
            self.badgeText = badgeText
            self.transitType = transitType
        }

        var sourceBadgeText: String? {
            source == .schedule ? "Scheduled" : nil
        }

        func displayText(at now: Date) -> String {
            guard let time else { return text }
            return "\(text) · \(JourneyPresentationState.displayTime(time, relativeTo: now))"
        }
    }

    struct TimingMessage: Equatable, Codable {
        let title: String
        let detail: String
        let nextAction: String?

        init(title: String, detail: String, nextAction: String? = nil) {
            self.title = title
            self.detail = detail
            self.nextAction = nextAction
        }
    }

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
    let nextLegShortRouteName: String?
    let journeyArrival: Date?
    let currentLegArrival: Date?
    let etaStatusText: String?
    let timingWarning: TimingMessage?
    let departureRecommendation: TimingMessage?
    let nextTimingAction: String?
    let timingSteps: [TimingStep]

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func displayTime(_ date: Date, relativeTo now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining > 0 && remaining < 3600 {
            return "in \(TransitCountdown.minutes(until: date, from: now)) min"
        }
        return clock(date)
    }

    private static func timePhrase(_ date: Date, relativeTo now: Date) -> String {
        let display = displayTime(date, relativeTo: now)
        return display.hasPrefix("in ") ? display : "at \(display)"
    }

    static func etaText(_ date: Date, relativeTo now: Date, isCurrentLeg: Bool = false) -> String {
        let prefix = isCurrentLeg ? "Leg:" : "Arrive"
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return isCurrentLeg ? "Leg: arriving" : "Arriving" }
        if remaining < 3600 {
            let minutes = Int(ceil(remaining / 60))
            return isCurrentLeg ? "Leg: \(minutes) min" : "Arrive in \(minutes) min"
        }
        return "\(prefix) \(clock(date))"
    }

    private static func minutes(_ duration: TimeInterval) -> String {
        let count = max(0, Int(ceil(duration / 60)))
        return "\(count) min"
    }

    private static func consequenceText(nextDeparture: Date?, isLastService: Bool, relativeTo now: Date?) -> String {
        if isLastService { return "This is the last service." }
        if let nextDeparture {
            let time = now.map { displayTime(nextDeparture, relativeTo: $0) } ?? clock(nextDeparture)
            return "The next service is \(time.hasPrefix("in ") ? time : "at \(time)")."
        }
        return "Missing it means a long wait."
    }

    static func warningMessage(
        warning: ConnectionWarning,
        routeName: String,
        stopName: String,
        boardingTime: Date,
        availableTime: TimeInterval,
        nextAlternativeDeparture: Date?,
        isLastService: Bool,
        replacementDeparture: Date?,
        replacementArrival: Date?,
        relativeTo now: Date? = nil
    ) -> TimingMessage? {
        let service = "\(routeName) at \(stopName)"
        let boarding = now.map { displayTime(boardingTime, relativeTo: $0) } ?? clock(boardingTime)
        let boardingPhrase = boarding.hasPrefix("in ") ? boarding : "at \(boarding)"
        switch warning {
        case .none, .tight:
            return nil
        case .highConsequence:
            return TimingMessage(
                title: "Don’t miss this connection",
                detail: "Board \(service) \(boardingPhrase). \(consequenceText(nextDeparture: nextAlternativeDeparture, isLastService: isLastService, relativeTo: now))"
            )
        case .tightHighConsequence:
            let timeText = availableTime < 60 ? "Less than a minute" : "About \(minutes(availableTime))"
            return TimingMessage(
                title: "Move quickly for \(routeName)",
                detail: "\(timeText) remains after reaching \(stopName). \(consequenceText(nextDeparture: nextAlternativeDeparture, isLastService: isLastService, relativeTo: now))",
                nextAction: "Hurry to \(stopName) for \(routeName) \(boardingPhrase)"
            )
        case .likelyMiss:
            let explanation = "Current estimates leave too little time for \(service) \(boardingPhrase)."
            if let replacementDeparture {
                let replacement = now.map { displayTime(replacementDeparture, relativeTo: $0) } ?? clock(replacementDeparture)
                let arrival = replacementArrival.map { arrivalDate in
                    " Arrive \(now.map { displayTime(arrivalDate, relativeTo: $0) } ?? clock(arrivalDate))."
                } ?? ""
                return TimingMessage(
                    title: "Your connection has changed",
                    detail: "\(explanation) Take the service \(replacement.hasPrefix("in ") ? replacement : "at \(replacement)") instead.\(arrival)",
                    nextAction: "Take \(routeName) \(replacement.hasPrefix("in ") ? replacement : "at \(replacement)") instead"
                )
            }
            return TimingMessage(
                title: "Checking your next connection",
                detail: "\(explanation) A new journey ETA isn’t available yet.\(isLastService ? " This is the last service." : "")",
                nextAction: "Check the \(routeName) connection at \(stopName)"
            )
        }
    }

    private static func inAppWarningMessage(for journey: JourneyState, timing: JourneyTimingPlan?, relativeTo now: Date) -> TimingMessage? {
        guard let context = journey.timingContext,
              context.showsConnectionWarning,
              let timing else { return nil }

        let connection: JourneyConnectionTiming?
        if let itinerary = timing.selectedItinerary {
            connection = itinerary.connections.first {
                $0.arrivingLegId == context.timingLegId
            }
        } else {
            connection = timing.monitoredConnection
        }
        guard let connection,
              connection.arrivingLegId == context.timingLegId else { return nil }
        if context.isOnboard {
            guard connection.arrivingTripId == context.onboardTripId else { return nil }
        }

        let departingLeg = journey.legOrder.first { $0.id == connection.departingLegId }
        let routeName = departingLeg.map { getShortRouteName(for: $0) } ?? "connecting service"
        let stopName = departingLeg?.startStop.stopName ?? "your transfer"
        if connection.warning == .likelyMiss {
            guard timing.selectedItinerary == nil, connection.isHighConsequence else { return nil }
            return TimingMessage(
                title: "Connection at risk",
                detail: "Current estimates leave too little time for \(routeName) at \(stopName) \(timePhrase(connection.departure, relativeTo: now)). \(consequenceText(nextDeparture: connection.nextAlternativeDeparture, isLastService: connection.isLastService, relativeTo: now))"
            )
        }
        return warningMessage(
            warning: connection.warning,
            routeName: routeName,
            stopName: stopName,
            boardingTime: connection.departure,
            availableTime: connection.physicalSlack,
            nextAlternativeDeparture: connection.nextAlternativeDeparture,
            isLastService: connection.isLastService,
            replacementDeparture: nil,
            replacementArrival: nil,
            relativeTo: now
        )
    }

    private static func timingSteps(for itinerary: JourneyTimingItinerary, legs: [ResolvedLeg]) -> [TimingStep] {
        var steps: [TimingStep] = []
        for (index, timedLeg) in itinerary.legs.enumerated() {
            guard let leg = legs.first(where: { $0.id == timedLeg.resolvedLegId }) else { continue }
            steps.append(TimingStep(
                iconName: leg.transitType.iconName,
                text: "Board at \(leg.startStop.stopName)",
                time: timedLeg.departure,
                source: timedLeg.boardingTime.source,
                badgeText: getShortRouteName(for: leg),
                transitType: leg.transitType
            ))
            steps.append(TimingStep(
                iconName: "mappin.circle",
                text: "Arrive at \(leg.endStop.stopName)",
                time: timedLeg.arrival,
                source: timedLeg.arrivalTime.source,
                transitType: leg.transitType
            ))
            if index < itinerary.connections.count {
                let connection = itinerary.connections[index]
                if connection.minimumTransferDuration > 0 {
                    let arrivingLeg = legs.first { $0.id == connection.arrivingLegId }
                    let departingLeg = legs.first { $0.id == connection.departingLegId }
                    let sameStation: Bool
                    if let arrivingLeg, let departingLeg {
                        sameStation = arrivingLeg.endStop.stationId == departingLeg.startStop.stationId
                            || arrivingLeg.endStop.stopName.localizedCaseInsensitiveCompare(departingLeg.startStop.stopName) == .orderedSame
                    } else {
                        sameStation = false
                    }
                    let walkDestination = sameStation
                        ? "the \(departingLeg?.transitType.rawValue ?? "next") platform"
                        : (departingLeg?.startStop.stopName ?? "the next boarding stop")
                    steps.append(TimingStep(
                        iconName: "figure.walk",
                        text: "Walk to \(walkDestination) · \(minutes(connection.minimumTransferDuration))"
                    ))
                }
                if connection.platformWaitDuration > 0 {
                    steps.append(TimingStep(
                        iconName: "clock",
                        text: "Wait about \(minutes(connection.platformWaitDuration))"
                    ))
                }
            }
        }
        return steps
    }
    
    private static func getShortRouteName(for leg: ResolvedLeg) -> String {
        RoutePresentation(routeId: leg.mbtaRouteId, transitType: leg.transitType).badgeText
    }
    
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
            self.nextLegShortRouteName = nil
            self.journeyArrival = nil
            self.currentLegArrival = nil
            self.etaStatusText = nil
            self.timingWarning = nil
            self.departureRecommendation = nil
            self.nextTimingAction = nil
            self.timingSteps = []
            return
        }

        let context = journey.timingContext
        let hidesUnconfirmedOnboardTiming = context?.isOnboard == true
            && context?.onboardTripId == nil
        let matchingTiming = context.flatMap { current in
            journey.timingState.timing.flatMap { $0.context == current ? $0 : nil }
        }
        let timing = hidesUnconfirmedOnboardTiming ? nil : matchingTiming
        let now = Date()
        self.journeyArrival = timing?.destinationArrival
        if let timing {
            switch timing.status {
            case .idle, .current: self.etaStatusText = nil
            case .loading: self.etaStatusText = "Finding journey ETA"
            case .stale: self.etaStatusText = "Updating live times"
            case .unavailable: self.etaStatusText = "Journey ETA unavailable"
            }
        } else {
            self.etaStatusText = nil
        }
        let legArrival = timing?.currentLegArrival?.time
            ?? timing?.selectedItinerary?.legs.first?.arrival
        self.currentLegArrival = journey.timingContext?.allowsRecommendation == false
            && legArrival != timing?.destinationArrival ? legArrival : nil
        if let recommendation = timing?.recommendedDeparture,
           journey.timingContext?.allowsRecommendation == true,
           let leg = journey.legOrder.first(where: { $0.id == recommendation.resolvedLegId }) {
            self.departureRecommendation = TimingMessage(
                title: "Recommended boarding",
                detail: "Board \(Self.getShortRouteName(for: leg)) at \(leg.startStop.stopName) · \(Self.displayTime(recommendation.boardingTime.time, relativeTo: now))"
            )
        } else {
            self.departureRecommendation = nil
        }
        self.timingWarning = Self.inAppWarningMessage(for: journey, timing: timing, relativeTo: now)
        self.timingSteps = timing?.selectedItinerary.map {
            Self.timingSteps(for: $0, legs: journey.legOrder)
        } ?? []
        var nextAction: String?
        if let context = journey.timingContext,
           let timedLeg = timing?.selectedItinerary?.legs.first,
           let leg = journey.legOrder.first(where: { $0.id == timedLeg.resolvedLegId }) {
            switch context.phase {
            case .approachingBoarding:
                nextAction = "Go to \(leg.startStop.stopName); board \(Self.getShortRouteName(for: leg)) \(Self.timePhrase(timedLeg.departure, relativeTo: now))"
            case .atBoardingStop:
                nextAction = "Board \(Self.getShortRouteName(for: leg)) at \(leg.startStop.stopName) \(Self.timePhrase(timedLeg.departure, relativeTo: now))"
            case .transferring:
                if journey.currentStop?.mbtaStopId != leg.startStop.mbtaStopId {
                    nextAction = "Walk to \(leg.startStop.stopName); board \(Self.getShortRouteName(for: leg)) \(Self.timePhrase(timedLeg.departure, relativeTo: now))"
                } else {
                    nextAction = "Board \(Self.getShortRouteName(for: leg)) at \(leg.startStop.stopName) \(Self.timePhrase(timedLeg.departure, relativeTo: now))"
                }
            case .onboard:
                nextAction = "Get off at \(leg.endStop.stopName) \(Self.timePhrase(timedLeg.arrival, relativeTo: now))"
            }
        } else if journey.timingContext?.isOnboard == true,
                  let currentLeg = timing?.currentLeg,
                  let leg = journey.legOrder.first(where: { $0.id == currentLeg.resolvedLegId }) {
            nextAction = "Get off at \(leg.endStop.stopName) \(Self.timePhrase(currentLeg.arrival, relativeTo: now))"
        }
        self.nextTimingAction = journey.timingContext?.isOnboard == true
            ? nextAction
            : (self.timingWarning?.nextAction ?? nextAction)
        
        // shortRouteName
        if let leg = journey.currentLeg {
            self.shortRouteName = Self.getShortRouteName(for: leg)
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
            let nextLeg = journey.legOrder[nextIndex]
            self.nextLegTransitType = nextLeg.transitType
            self.nextLegShortRouteName = Self.getShortRouteName(for: nextLeg)
        } else {
            self.nextLegTransitType = nil
            self.nextLegShortRouteName = nil
        }
    }
}

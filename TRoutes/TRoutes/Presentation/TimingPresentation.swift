//
//  TimingPresentation.swift
//  TRoutes
//
//  Created by Adam Post on 9/20/26.
//

import Foundation

//Information for updated Warnings
struct ConnectionWarningChangedDetails: Equatable, Sendable {
    let stopName: String? //what stop were we switching to?
    let departingRouteId: String? //the next leg we're switching to at connection
    let transitType: TransitType? //what vehicle is next leg using?
    
    let boardingTime: SelectedStopTime?
    let destinationArrival: Date? //overall ETA
    
    let previousBoardingTime: SelectedStopTime?
    let oldArrival: Date? //when were we originally gonna arrive at destination??
    let previousWarning: ConnectionWarning?
    let warning: ConnectionWarning?

    let journeyRemainsPossible:Bool

    init(boardingTime: SelectedStopTime?, eta: Date?, previousBoardingTime: SelectedStopTime?, previousEta: Date?, departingLeg: ResolvedLeg?, previousWarning: ConnectionWarning?, warning: ConnectionWarning?) {
        self.boardingTime = boardingTime
        self.destinationArrival = eta
        self.departingRouteId = departingLeg?.mbtaRouteId
        self.stopName = departingLeg?.startStop.stopName
        self.transitType = departingLeg?.transitType
        self.previousBoardingTime = previousBoardingTime
        self.oldArrival = previousEta
        self.previousWarning = previousWarning
        self.warning = warning
        self.journeyRemainsPossible = eta != nil
    }
}

//Information for Transfers
//Information for Initial Boarding

struct BoardingNoticeDetails: Equatable, Sendable {
    //Transfer Ex. "Transfer to ("boardingStopName" if previousStopName != boardingStopName "on") the "(route)." (vehicle) (arrives/departs) at (time/in x min)"
    
    let boardingLegId: String //which leg are we trying to board?
    let routeId: String//what route? clean inside notificationmanager
    let transitType: TransitType //what
    let directionDestination: String
    
    let previousStopName: String? //what stop are we coming from (does not exist on intial boarding)
    let boardingStopName: String //what stop are we going to?
    
    let boardingTime: SelectedStopTime?
    
    //Adds warning message if applicable
    let connectionWarning: ConnectionWarning
    
    //Initial Ex. "Board the (route) on the (
    let recommendation:RecommendedDeparture? //used to figure out if initial boarding or not
    

    init?(recommendation: RecommendedDeparture?, timingPlan: JourneyTimingPlan, legs: [ResolvedLeg]) {
        if let recommendation {
            guard let boardingLeg = legs.first(where: { $0.id == recommendation.resolvedLegId }) else {
                return nil
            }
            let connection = timingPlan.selectedItinerary?.connections.first {
                $0.arrivingLegId == recommendation.resolvedLegId
                    && $0.arrivingTripId == recommendation.tripId
            }

            self.boardingLegId = recommendation.resolvedLegId.uuidString
            self.routeId = boardingLeg.mbtaRouteId
            self.transitType = boardingLeg.transitType
            self.directionDestination = boardingLeg.transitDirection?.destination ?? boardingLeg.endStop.stopName
            self.previousStopName = nil
            self.boardingStopName = boardingLeg.startStop.stopName
            self.boardingTime = recommendation.boardingTime
            self.connectionWarning = connection?.warning ?? .none
            self.recommendation = recommendation
            return
        }

        guard let connection = timingPlan.monitoredConnection,
              let arrivingLeg = legs.first(where: { $0.id == connection.arrivingLegId }),
              let boardingLeg = legs.first(where: { $0.id == connection.departingLegId }) else {
            return nil
        }

        self.boardingLegId = connection.departingLegId.uuidString
        self.routeId = boardingLeg.mbtaRouteId
        self.transitType = boardingLeg.transitType
        self.directionDestination = boardingLeg.transitDirection?.destination ?? boardingLeg.endStop.stopName
        self.previousStopName = arrivingLeg.endStop.stopName
        self.boardingStopName = boardingLeg.startStop.stopName
        self.boardingTime = connection.boardingTime
        self.connectionWarning = connection.warning
        self.recommendation = nil
    }

    init(leg: ResolvedLeg) {
        self.boardingLegId = leg.id.uuidString
        self.routeId = leg.mbtaRouteId
        self.transitType = leg.transitType
        self.directionDestination = leg.transitDirection?.destination ?? leg.endStop.stopName
        self.previousStopName = nil
        self.boardingStopName = leg.startStop.stopName
        self.boardingTime = nil
        self.connectionWarning = .none
        self.recommendation = nil
    }
}


//About to transfer or arrive at final!
struct UpcomingArrivalNoticeDetails: Equatable, Sendable {
    //Ex. "Arrive at (stopName) in (x minutes)!"
    //May want to make stops away dynamic, but for now not needed, this is getting out of hand
    let resolvedLegId: UUID //leg we're on
    let tripId: String
    let routeId: String
    let directionDestination: String
    let stopName: String
    let arrival:Date? //real-time arrival only; nil keeps the one-stop-away alert without presenting schedule as live
    
    // Transfer information
    
    //Ex. add onto above example "Transfer to ("transferStopName" if transferStopName != stopName + "on") the "(route) once you arrive"
    
    let transferTransitType: TransitType?
    let transferStopName:String? // (don't display if same station name)
    let transferRouteId:String?
    
    let connectionWarning:ConnectionWarning

    init?(legTiming: JourneyLegTiming, connectionTiming: JourneyConnectionTiming?, legs: [ResolvedLeg]) {
        guard let leg = legs.first(where: { $0.id == legTiming.resolvedLegId }) else {
            return nil
        }

        self.resolvedLegId = legTiming.resolvedLegId
        self.tripId = legTiming.tripId
        self.routeId = legTiming.routeId
        self.directionDestination = leg.transitDirection?.destination ?? leg.endStop.stopName
        self.stopName = leg.endStop.stopName
        self.arrival = legTiming.arrivalTime.source == .prediction
            && legTiming.arrivalTime.event == .arrival
            ? legTiming.arrival
            : nil

        if let connectionTiming {
            guard let transferLeg = legs.first(where: { $0.id == connectionTiming.departingLegId }) else {
                return nil
            }
            self.transferTransitType = transferLeg.transitType
            self.transferStopName = transferLeg.startStop.stopName
            self.transferRouteId = transferLeg.mbtaRouteId
            self.connectionWarning = connectionTiming.warning
        } else {
            self.transferTransitType = nil
            self.transferStopName = nil
            self.transferRouteId = nil
            self.connectionWarning = .none
        }
    }
}

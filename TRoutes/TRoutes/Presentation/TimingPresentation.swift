//
//  TimingPresentation.swift
//  TRoutes
//
//  Created by Adam Post on 9/20/26.
//

import Foundation

struct NoticeTime: Equatable, Sendable {
    let time: Date?
    let source: TimingSource?
}

//Information for updated Warnings
struct ConnectionWarningChangedDetails: Equatable, Sendable {
    let stopName: String? //what stop were we switching to?
    let departingRouteId: String? //the next leg we're switching to at connection
    let transitType: TransitType? //what vehicle is next leg using?
    
    let departure: NoticeTime? //when is next leg departing?
    let destinationArrival: Date? //overall ETA
    
    let oldTime:NoticeTime? //when was train supposed to arrive or depart?
    let oldArrival: Date? //when were we originally gonna arrive at destination??
    let warning: ConnectionWarning?
    
    let journeyRemainsPossible:Bool

    init?(departure:NoticeTime?, eta:Date?, previousDeparture:NoticeTime?, previousEta:Date?, departingLeg:ResolvedLeg?, warning:ConnectionWarning?) {
        self.departure = departure
        self.destinationArrival = nil
        self.departingRouteId = departingLeg?.mbtaRouteId
        self.stopName = departingLeg?.startStop.stopName
        self.transitType = departingLeg?.transitType
        self.oldTime = previousDeparture
        self.oldArrival = previousEta
        self.warning = warning
    }
}

//Information for Transfers
//Information for Initial Boarding

struct BoardingNoticeDetails: Equatable, Sendable {
    let boardingLegId: String //which leg are we trying to board?
    let routeId: String//what route?
    let transitType: TransitType //what
    let directionDestination: String
    let stopName: String //what stop are we going to?
    let arrivalTime: NoticeTime? //(8 min, predicted)
    let departureTime: NoticeTime?// fallback (8:12 AM, scheduled)
    let connectionWarning: ConnectionWarning
    let recommendation:RecommendedDeparture? //used to figure out if initial boarding or not
    

    init?(recommendation: RecommendedDeparture?, timingPlan: JourneyTimingPlan, legs: [ResolvedLeg]) {
        
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
    let arrival:Date //when are we getting there, must be real time, not possibly scheduled
    
    // Transfer information
    
    //Ex. add onto above example "Transfer to ("transferStopName" if transferStopName != stopName + "on") the "routeId (cleaned) once you arrive"
    
    let transferTransitType: TransitType?
    let transferStopName:String? // (don't display if same station name)
    let transferRouteId:String?
    
    let connectionWarning:ConnectionWarning

    init?(legTiming: JourneyLegTiming, connectionTiming: JourneyConnectionTiming?, legs: [ResolvedLeg]) {
        guard let leg = legs.first(where: { $0.id == legTiming.resolvedLegId }) else {
            return nil
        }

       // self.connection = connectionTiming.flatMap { ConnectionWarningDetails(timing: $0, legs: legs) }
    }
}

//
//  ScheduleResponse.swift
//  TRoutes
//
//  Created by Adam Post on 7/19/26.
//

import Foundation

struct ScheduleResponse: Codable {
    let data: [ScheduleData]
}

struct TransitSchedule: Codable, Equatable, Hashable {
    let display: String
    let vehicleId: String?
    let ScheduleId: String
    let tripId: String?
    let stopId: String?
    let routeId: String?
    let headsign: String?
    let directionId: Int?
    let stopSequence: Int?
    
    var asPrediction: TransitPrediction {
        TransitPrediction(
            display: self.display,
            vehicleId: self.vehicleId,
            predictionId: self.ScheduleId,
            tripId: self.tripId,
            stopId: self.stopId,
            routeId: self.routeId,
            headsign: self.headsign,
            directionId: self.directionId,
            stopSequence: self.stopSequence
        )
    }
}

struct ScheduleData: Codable {
    let type: String
    let id: String
    let attributes: ScheduleAttributes
    let relationships: ScheduleRelationships
}

struct ScheduleAttributes: Codable {
    let updateType: String?
    let tripHeadsign: String?
    let stopSequence: Int?
    let status: String?
    let scheduleRelationship: String?
    let revenueStatus: String?
    let lastTrip: Bool?
    let directionId: Int?
    let departureUncertainty: Int?
    let departureTime: String?
    let arrivalUncertainty: Int?
    let arrivalTime: String?
}

struct ScheduleRelationships: Codable {
    let vehicle: RelationshipSingle?
    let trip: RelationshipSingle?
    let stop: RelationshipSingle?
    let schedule: RelationshipSingle?
    let route: RelationshipSingle?
    let alerts: RelationshipMultiple?
}


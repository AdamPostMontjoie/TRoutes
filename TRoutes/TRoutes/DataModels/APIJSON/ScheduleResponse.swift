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

    /// Short branch label for display (e.g., "Ashmont", "B", "Braintree")
    var branchLabel: String? {
        // Green Line
        if let routeId, routeId.hasPrefix("Green-") {
            return routeId.replacingOccurrences(of: "Green-", with: "")
        }
        //Red Line
        if let headsign, !headsign.isEmpty {
            if let routeId, routeId == "Red" {
                return headsign
            }
        }
        return nil
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


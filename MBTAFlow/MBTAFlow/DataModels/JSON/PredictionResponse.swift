//
//  PredictionResponse.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/4/26.
//

import Foundation

// 1. The Root Level
struct PredictionResponse: Codable {
    let data: [PredictionData]
    // You can omit the "links" object entirely if you do not need to use it.
    // Swift will simply ignore any JSON keys you do not explicitly define.
}

// 2. The Data Array Elements
struct PredictionData: Codable {
    let type: String
    let id: String
    let attributes: PredictionAttributes
    let relationships: PredictionRelationships
}

// 3. The Attributes (The actual prediction data)
struct PredictionAttributes: Codable {
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
    
    // Note: Use Optionals (?) for properties that might be null in the API response.
    // For example, the first stop on a route will have a null arrivalTime.
}

// 4. The Relationships (Pointers to other objects)
struct PredictionRelationships: Codable {
    let vehicle: RelationshipSingle?
    let trip: RelationshipSingle?
    let stop: RelationshipSingle?
    let schedule: RelationshipSingle?
    let route: RelationshipSingle?
    let alerts: RelationshipMultiple?
}

// 5. Relationship Helpers
struct RelationshipSingle: Codable {
    let data: RelationshipNode?
}

struct RelationshipMultiple: Codable {
    let data: [RelationshipNode]?
}

struct RelationshipNode: Codable {
    let type: String
    let id: String
}

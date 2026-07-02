//
//  VehicleResponse.swift
//  TRoutes
//
//  Created by Adam Post on 6/27/26.
//

struct VehicleResponse: Codable {
    let data: VehicleResponseData
}

struct VehicleResponseData: Codable {
    let id: String
    let attributes: VehicleAttributes
    let relationships: VehicleRelationships?
}

struct VehicleAttributes: Codable {
    let bearing: Double?
    let currentStatus: String?
    let currentStopSequence: Int?
    let directionId: Int?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
}

struct VehicleData: Codable, Equatable {
    let id: String
    let bearing: Double?
    let directionId: Int?
    let routeId: String?
    let tripId: String?
    let stopId: String?
    let latitude: Double?
    let longitude: Double?
    let currentStopSequence: Int?
    let currentStatus: String?
    let speed: Double?
}

struct VehicleRelationships: Codable {
    let route: RelationshipSingle?
    let stop: RelationshipSingle?
    let trip: RelationshipSingle?
}

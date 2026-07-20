//
//  LiveTripResponse.swift
//  TRoutes
//
//  Created by Adam Post on 7/3/26.
//

struct LiveTripPath: Equatable {
    let tripId: String
    let vehicleId: String?
    let routePatternId: String?
    let vehicleStopId: String?
    let vehicleStatus: String?
    let vehicleApiStopSequence: Int?
    let stops: [LiveTripStop]
    let predictions: [LiveTripPrediction]
}

struct LiveTripStop: Equatable {
    let stopId: String
    let parentStationId: String?
    let name: String?
    let orderIndex: Int
}

struct LiveTripPrediction: Equatable {
    let stopId: String
    let apiStopSequence: Int?
    let arrivalTime: String?
    let departureTime: String?
}

struct TripPathResponse: Codable {
    let data: TripPathData
    let included: [TripPathIncluded]?
}

struct TripPathData: Codable {
    let id: String
    let relationships: TripPathRelationships
}

struct TripPathRelationships: Codable {
    let vehicle: RelationshipSingle?
    let routePattern: RelationshipSingle?
    let stops: RelationshipMultiple?
    let predictions: RelationshipMultiple?
}

struct TripPathIncluded: Codable {
    let type: String
    let id: String
    let attributes: TripPathIncludedAttributes?
    let relationships: TripPathIncludedRelationships?
}

struct TripPathIncludedAttributes: Codable {
    let name: String?
    let currentStatus: String?
    let currentStopSequence: Int?
    let stopSequence: Int?
    let arrivalTime: String?
    let departureTime: String?
}

struct TripPathIncludedRelationships: Codable {
    let parentStation: RelationshipSingle?
    let stop: RelationshipSingle?
}

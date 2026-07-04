//
//  LiveTripResponse.swift
//  TRoutes
//
//  Created by Adam Post on 7/3/26.
//

struct LiveTripTrackingData: Equatable {
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

struct TripTrackingResponse: Codable {
    let data: TripTrackingData
    let included: [TripTrackingIncluded]?
}

struct TripTrackingData: Codable {
    let id: String
    let relationships: TripTrackingRelationships
}

struct TripTrackingRelationships: Codable {
    let vehicle: RelationshipSingle?
    let routePattern: RelationshipSingle?
    let stops: RelationshipMultiple?
    let predictions: RelationshipMultiple?
}

struct TripTrackingIncluded: Codable {
    let type: String
    let id: String
    let attributes: TripTrackingIncludedAttributes?
    let relationships: TripTrackingIncludedRelationships?
}

struct TripTrackingIncludedAttributes: Codable {
    let name: String?
    let currentStatus: String?
    let currentStopSequence: Int?
    let stopSequence: Int?
    let arrivalTime: String?
    let departureTime: String?
}

struct TripTrackingIncludedRelationships: Codable {
    let parentStation: RelationshipSingle?
    let stop: RelationshipSingle?
}

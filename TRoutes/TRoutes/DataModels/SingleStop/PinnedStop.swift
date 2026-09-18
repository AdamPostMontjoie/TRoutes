//
//  PinnedStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/19/26.
//

import Foundation

struct PinnedStop: Equatable, Codable, Identifiable, PredictionTarget {
    var id: UUID = UUID()
    var stationId: String
    var platformId: String
    var routeId: String
    var directionId: Int
    var stopName: String
    var transitType: TransitType
    var directionDestinations: [String]
    var predictionRouteId: String { routeId }
    var predictionStopIds: [String] { [stationId] } // Use stationId to get all platforms
    var predictionDirectionId: Int { directionId }
}

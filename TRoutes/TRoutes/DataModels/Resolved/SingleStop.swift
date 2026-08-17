//
//  SingleStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import Foundation

struct SingleStop: Equatable, Codable, Identifiable, PredictionTarget {
    var id: UUID = UUID()
    var stationId: String
    var platformId: String
    var routeId: String
    var directionId: Int
    var stopName: String
    var transitType: TransitType
    var directionDestinations: [String]
    
    // MARK: - PredictionTarget
    var predictionRouteId: String { routeId }
    var predictionStopIds: [String] { [stationId] } // Use stationId to get all platforms
    var predictionDirectionId: Int { directionId }
}

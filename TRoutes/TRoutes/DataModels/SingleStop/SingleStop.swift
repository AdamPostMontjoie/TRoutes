//
//  SingleStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import Foundation

/// A saved stop: station + route, direction is swipeable (not locked).
/// Does NOT conform to PredictionTarget — the banner manages active direction.
struct SingleStop: Equatable, Codable, Identifiable {
    var id: UUID = UUID()
    var stationId: String
    var platformId: String
    var routeId: String
    var stopName: String
    var transitType: TransitType
    var directionDestinations: [String]  // [0] = direction 0 name, [1] = direction 1 name
}

//
//  Station.swift
//  TRoutes
//
//  Created by Adam Post on 8/19/26.
//

import Foundation

/// Lightweight view model representing a station and all stops serving it.
/// Used for search results and the station detail view.
struct Station: Equatable, Identifiable {
    var id: String { stationId }
    var stationId: String
    var stationName: String
    var latitude: Double
    var longitude: Double
    var stops: [StationStop]
}

/// A single stop serving a station, with platform and direction info.
struct StationStop: Equatable, Identifiable {
    var id: String { routeId }
    var routeId: String
    var routeName: String
    var transitType: TransitType
    var platformId: String
    var directionDestinations: [String]  // [0] = direction 0 name, [1] = direction 1 name
}

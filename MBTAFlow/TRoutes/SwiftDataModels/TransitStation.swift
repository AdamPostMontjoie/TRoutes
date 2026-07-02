//
//  TransitStation.swift
//  TRoutes
//
//  Created by Adam Post on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TransitStation {
    @Attribute(.unique) var stationId: String
    var name: String
    var latitude: Double
    var longitude: Double
    var municipality: String?
    var monitoringMode: String
    var platformIds: [String]
    @Relationship(deleteRule: .nullify, inverse: \TransitPlatform.station)
    var platforms: [TransitPlatform]

    init(
        stationId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        municipality: String? = nil,
        monitoringMode: String = "aboveground",
        platformIds: [String] = [],
        platforms: [TransitPlatform] = []
    ) {
        self.stationId = stationId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.municipality = municipality
        self.monitoringMode = monitoringMode
        self.platformIds = platformIds
        self.platforms = platforms
    }
}

//
//  TransitPlatform.swift
//  TRoutes
//
//  Created by Adam Post on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TransitPlatform {
    @Attribute(.unique) var platformId: String
    var stationId: String
    var name: String
    var latitude: Double
    var longitude: Double
    var transitType: String
    var patternIds: [String]
    var station: TransitStation?
    @Relationship(deleteRule: .nullify, inverse: \TransitSequenceEdge.platform)
    var sequenceEdges: [TransitSequenceEdge]

    init(
        platformId: String,
        stationId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        transitType: String,
        patternIds: [String] = [],
        station: TransitStation? = nil,
        sequenceEdges: [TransitSequenceEdge] = []
    ) {
        self.platformId = platformId
        self.stationId = stationId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.transitType = transitType
        self.patternIds = patternIds
        self.station = station
        self.sequenceEdges = sequenceEdges
    }
}

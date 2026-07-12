//
//  TransitEdge.swift
//  TRoutes
//
//  Created by Adam Post on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TransitSequenceEdge {
    var patternId: String
    var routeId: String
    var directionId: Int
    var sequenceNumber: Int
    var platformId: String
    var stationId: String
    var sortIndex: Int
    var pattern: TransitPattern?
    var platform: TransitPlatform?

    init(
        patternId: String,
        routeId: String,
        directionId: Int,
        sequenceNumber: Int,
        platformId: String,
        stationId: String,
        sortIndex: Int,
        pattern: TransitPattern? = nil,
        platform: TransitPlatform? = nil
    ) {
        self.patternId = patternId
        self.routeId = routeId
        self.directionId = directionId
        self.sequenceNumber = sequenceNumber
        self.platformId = platformId
        self.stationId = stationId
        self.sortIndex = sortIndex
        self.pattern = pattern
        self.platform = platform
    }
}

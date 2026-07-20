//
//  ResolvedUserRoutes.swift
//  TRoutes
//
//  Created by Adam Post on 7/3/26.
//

import Foundation

struct ResolvedStop:Equatable, Codable, Identifiable {
    var id: UUID
    var sourceLegId: UUID
    var legIndex: Int
    var legStopIndex: Int
    var patternStopIndex: Int
    var patternEdgeSequenceNumber: Int
    var platformId: String
    var stationId: String
    var mbtaStopId: String
    var mbtaRouteId: String
    var mbtaDirectionId: Int
    var stopName: String
    var longitude: Double
    var latitude: Double
    var address: String // display on review feature
    var acceptableStopIds: [String]
    var journeyRole: JourneyStopRole = .boarding
    var monitoringMode:MonitoringMode
    var transitType: GTFSTransitType
    var overlapsWithNext: Bool
    var stopType: StopType
    
    init(
        id: UUID = UUID(),
        sourceLegId: UUID,
        legIndex: Int,
        legStopIndex: Int,
        patternStopIndex: Int,
        patternEdgeSequenceNumber: Int,
        platformId: String,
        stationId: String,
        mbtaStopId: String,
        mbtaRouteId: String,
        mbtaDirectionId: Int,
        stopName: String,
        longitude: Double,
        latitude: Double,
        address: String,
        acceptableStopIds: [String],
        journeyRole: JourneyStopRole = .boarding,
        monitoringMode: MonitoringMode,
        transitType: GTFSTransitType,
        overlapsWithNext: Bool = true
    ) {
        self.id = id
        self.sourceLegId = sourceLegId
        self.legIndex = legIndex
        self.legStopIndex = legStopIndex
        self.patternStopIndex = patternStopIndex
        self.patternEdgeSequenceNumber = patternEdgeSequenceNumber
        self.platformId = platformId
        self.stationId = stationId
        self.mbtaStopId = mbtaStopId
        self.mbtaRouteId = mbtaRouteId
        self.mbtaDirectionId = mbtaDirectionId
        self.stopName = stopName
        self.longitude = longitude
        self.latitude = latitude
        self.address = address
        self.acceptableStopIds = acceptableStopIds
        self.journeyRole = journeyRole
        self.stopType = journeyRole.stopType
        self.monitoringMode = monitoringMode
        self.transitType = transitType
        self.overlapsWithNext = overlapsWithNext
    }
}

struct ResolvedPatternStop: Equatable, Codable, Identifiable {
    var id: String {
        "\(patternStopIndex)-\(platformId)"
    }

    var patternStopIndex: Int
    var patternEdgeSequenceNumber: Int
    var platformId: String
    var stationId: String
    var stopName: String
    var monitoringMode: MonitoringMode
    var transitType: GTFSTransitType
}


struct ResolvedLeg: Equatable, Codable, Identifiable {
    var id: UUID
    var sourceLegId: UUID
    var legIndex: Int
    var startStop: ResolvedStop
    var endStop: ResolvedStop
    var mbtaRouteId: String
    var mbtaDirectionId: Int
    var transitType: TransitType
    var transitBranch: TransitBranch?
    var transitDirection: TransitDirection?
    var selectedPatternId: String
    var acceptablePatternIds: [String]
    var acceptableRouteIds: [String]
    var stops: [ResolvedStop]
    var patternStops: [ResolvedPatternStop]

    var stopsOnLeg:Int {
        stops.count
    }

    var originPatternStopIndex: Int {
        startStop.patternStopIndex
    }

    var destinationPatternStopIndex: Int {
        endStop.patternStopIndex
    }

    var originPatternEdgeSequenceNumber: Int {
        startStop.patternEdgeSequenceNumber
    }

    var destinationPatternEdgeSequenceNumber: Int {
        endStop.patternEdgeSequenceNumber
    }
    
    
    init(
        id: UUID = UUID(),
        sourceLegId: UUID,
        legIndex: Int,
        startStop: ResolvedStop,
        endStop: ResolvedStop,
        mbtaRouteId: String,
        mbtaDirectionId: Int,
        transitType: TransitType,
        selectedPatternId: String,
        acceptablePatternIds: [String] = [],
        acceptableRouteIds: [String] = [],
        transitBranch: TransitBranch? = nil,
        transitDirection: TransitDirection? = nil,
        stops: [ResolvedStop],
        patternStops: [ResolvedPatternStop]
    ) {
        self.id = id
        self.sourceLegId = sourceLegId
        self.legIndex = legIndex
        self.mbtaRouteId = mbtaRouteId
        self.mbtaDirectionId = mbtaDirectionId
        self.transitType = transitType
        self.transitBranch = transitBranch
        self.transitDirection = transitDirection
        self.startStop = startStop
        self.endStop = endStop
        self.selectedPatternId = selectedPatternId
        self.acceptablePatternIds = acceptablePatternIds
        self.acceptableRouteIds = acceptableRouteIds
        self.stops = stops
        self.patternStops = patternStops
    }
}

struct ResolvedUserRoute: Equatable, Codable, Identifiable {
    var legs: [ResolvedLeg]
    var id: UUID
    var name: String
    var timeStamp: Date
}

enum ResolvedRouteError: Error, Equatable {
    case missingDirection(legId: UUID)
    case noSequenceEdges(legId: UUID, routeId: String, directionId: Int)
    case noValidPattern(legId: UUID, originStopId: String, destinationStopId: String)
    case missingPlatform(platformId: String)
    case missingStation(stationId: String)
}

private extension JourneyStopRole {
    var stopType: StopType {
        switch self {
        case .boarding:
            return .boardingStop
        case .transfer:
            return .transferStop
        case .intermediate:
            return .intermediateStop
        case .final:
            return .finalStop
        }
    }
}

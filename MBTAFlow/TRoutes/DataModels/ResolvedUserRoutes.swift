//
//  ResolvedUserRoutes.swift
//  TRoutes
//
//  Created by Adam Post on 7/3/26.
//

import Foundation

struct ResolvedStop: Codable, Equatable, Identifiable {
    var id: UUID
    var mbtaStopId: String
    var mbtaRouteId: String
    var mbtaDirectionId: Int
    var stopName: String
    var longitude: Double
    var latitude: Double
    var address: String // display on review feature
    var journeyRole: JourneyStopRole = .boarding
    var monitoringMode:MonitoringMode

    var stopType: StopType {
        get {
            switch journeyRole {
            case .boarding:
                return .boardingStop
            case .transfer:
                return .transferStop
            case .final:
                return .finalStop
            }
        }
        set {
            switch newValue {
            case .boardingStop:
                journeyRole = .boarding
            case .transferStop:
                journeyRole = .transfer(overlapsNext: overlapsWithNext)
            case .finalStop:
                journeyRole = .final
            }
        }
    }

    var overlapsWithNext: Bool {
        get {
            guard case let .transfer(overlapsNext) = journeyRole else {
                return false
            }
            return overlapsNext
        }
        set {
            guard case .transfer = journeyRole else {
                return
            }
            journeyRole = .transfer(overlapsNext: newValue)
        }
    }

    init(
        id: UUID = UUID(),
        mbtaStopId: String,
        mbtaRouteId: String,
        mbtaDirectionId: Int,
        stopName: String,
        longitude: Double,
        latitude: Double,
        address: String,
        journeyRole: JourneyStopRole = .boarding
    ) {
        self.id = id
        self.mbtaStopId = mbtaStopId
        self.mbtaRouteId = mbtaRouteId
        self.mbtaDirectionId = mbtaDirectionId
        self.stopName = stopName
        self.longitude = longitude
        self.latitude = latitude
        self.address = address
        self.journeyRole = journeyRole
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mbtaStopId
        case mbtaRouteId
        case mbtaDirectionId
        case stopName
        case longitude
        case latitude
        case address
        case journeyRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mbtaStopId = try container.decode(String.self, forKey: .mbtaStopId)
        mbtaRouteId = try container.decode(String.self, forKey: .mbtaRouteId)
        mbtaDirectionId = try container.decode(Int.self, forKey: .mbtaDirectionId)
        stopName = try container.decode(String.self, forKey: .stopName)
        longitude = try container.decode(Double.self, forKey: .longitude)
        latitude = try container.decode(Double.self, forKey: .latitude)
        address = try container.decode(String.self, forKey: .address)
        journeyRole = try container.decodeIfPresent(JourneyStopRole.self, forKey: .journeyRole) ?? .boarding
    }
}


struct ResolvedLeg: Equatable, Codable, Identifiable {
    var id: UUID
    var startStop: Stop
    var endStop: Stop
    var mbtaRouteId: String
    var transitType: TransitType
    var transitBranch: TransitBranch?
    var transitDirection: TransitDirection?
    var stopsOnLeg:Int?
    var stops: [ResolvedStop]?
    
    
    init(
        id: UUID = UUID(),
        startStop: Stop,
        endStop: Stop,
        mbtaRouteId: String,
        transitType: TransitType,
        transitBranch: TransitBranch? = nil,
        transitDirection: TransitDirection? = nil
    ) {
        self.id = id
        self.mbtaRouteId = mbtaRouteId
        self.transitType = transitType
        self.transitBranch = transitBranch
        self.transitDirection = transitDirection
        self.startStop = startStop
        self.endStop = endStop
        applyDirectionToStopsIfNeeded()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startStop
        case endStop
        case mbtaRouteId
        case transitType
        case transitBranch
        case transitDirection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startStop = try container.decode(Stop.self, forKey: .startStop)
        endStop = try container.decode(Stop.self, forKey: .endStop)
        mbtaRouteId = try container.decode(String.self, forKey: .mbtaRouteId)
        transitType = try container.decode(TransitType.self, forKey: .transitType)
        transitBranch = try container.decodeIfPresent(TransitBranch.self, forKey: .transitBranch)
        transitDirection = try container.decodeIfPresent(TransitDirection.self, forKey: .transitDirection)
        applyDirectionToStopsIfNeeded()
    }

    private mutating func applyDirectionToStopsIfNeeded() {
        guard let directionId = transitDirection?.directionId else { return }

        startStop.mbtaDirectionId = directionId
        endStop.mbtaDirectionId = directionId
    }
}

struct ResolvedUserRoute: Codable, Equatable, Identifiable {
    var legs: [Leg]
    var id: UUID
    var name: String
    var timeStamp: Date
}

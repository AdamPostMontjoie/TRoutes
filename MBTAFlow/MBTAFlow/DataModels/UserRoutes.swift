//
//  Locations.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//
import Foundation

struct Stop: Codable, Equatable, Identifiable {
    var id: UUID
    var mbtaStopId: String
    var mbtaRouteId: String
    var stopName: String
    var longitude: Double
    var latitude: Double
    var address: String // display on review feature
    var stopType: StopType = .boardingStop //default
    var overlapsWithNext: Bool = false // Default to false

    private enum CodingKeys: String, CodingKey {
        case id
        case mbtaStopId
        case mbtaRouteId
        case stopName
        case longitude
        case latitude
        case address
    }
}

enum StopType: Codable, Equatable {
    case boardingStop
    case transferStop
    case finalStop
}

struct Leg: Equatable, Codable, Identifiable {
    var id: UUID
    var startStop: Stop
    var endStop: Stop
    var mbtaRouteId: String
    var transitType: TransitType
    var transitBranch: TransitBranch?
    var transitDirection: TransitDirection?

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
        self.startStop = startStop
        self.endStop = endStop
        self.mbtaRouteId = mbtaRouteId
        self.transitType = transitType
        self.transitBranch = transitBranch
        self.transitDirection = transitDirection
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
    }
}

struct RouteStruct: Equatable, Identifiable {
    var legs: [Leg]
    var id: UUID
    var name: String
    var timeStamp: Date
}

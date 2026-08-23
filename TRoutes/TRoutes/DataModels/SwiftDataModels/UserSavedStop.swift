//
//  UserSavedStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import Foundation
import SwiftData

/// Protocol defining common properties for user-saved stops.
protocol BaseUserStop {
    var id: UUID { get set }
    var stationId: String { get set }
    var platformId: String { get set }
    var routeId: String { get set }
    var stopName: String { get set }
    var transitTypeRaw: String { get set }
    var directionDestinations: [String] { get set }
    var addedAt: Date { get set }
}

/// SwiftData model for persisting saved stops (direction is swipeable).
@Model
final class UserSavedStop: BaseUserStop {
    @Attribute(.unique) var id: UUID
    var stationId: String
    var platformId: String
    var routeId: String
    var stopName: String
    var transitTypeRaw: String
    var directionDestinations: [String]
    var addedAt: Date

    init(
        id: UUID = UUID(),
        stationId: String,
        platformId: String,
        routeId: String,
        stopName: String,
        transitTypeRaw: String,
        directionDestinations: [String] = [],
        addedAt: Date = Date()
    ) {
        self.id = id
        self.stationId = stationId
        self.platformId = platformId
        self.routeId = routeId
        self.stopName = stopName
        self.transitTypeRaw = transitTypeRaw
        self.directionDestinations = directionDestinations
        self.addedAt = addedAt
    }
}

/// SwiftData model for persisting pinned stops (direction is locked).
@Model
final class UserPinnedStop: BaseUserStop {
    @Attribute(.unique) var id: UUID
    var stationId: String
    var platformId: String
    var routeId: String
    var stopName: String
    var transitTypeRaw: String
    var directionDestinations: [String]
    var pinnedDirectionId: Int
    var addedAt: Date
    
    init(
        id: UUID = UUID(),
        stationId: String,
        platformId: String,
        routeId: String,
        stopName: String,
        transitTypeRaw: String,
        directionDestinations: [String] = [],
        pinnedDirectionId: Int,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.stationId = stationId
        self.platformId = platformId
        self.routeId = routeId
        self.stopName = stopName
        self.transitTypeRaw = transitTypeRaw
        self.directionDestinations = directionDestinations
        self.pinnedDirectionId = pinnedDirectionId
        self.addedAt = addedAt
    }
}

// MARK: - Conversions to value types

extension UserSavedStop {
    /// Convert a persisted saved stop to a SingleStop value type
    func toSingleStop() -> SingleStop {
        SingleStop(
            id: id,
            stationId: stationId,
            platformId: platformId,
            routeId: routeId,
            stopName: stopName,
            transitType: TransitType(rawValue: transitTypeRaw) ?? .bus,
            directionDestinations: directionDestinations
        )
    }
}

extension UserPinnedStop {
    /// Convert a persisted pinned stop to a PinnedStop value type.
    func toPinnedStop() -> PinnedStop {
        PinnedStop(
            id: id,
            stationId: stationId,
            platformId: platformId,
            routeId: routeId,
            directionId: pinnedDirectionId,
            stopName: stopName,
            transitType: TransitType(rawValue: transitTypeRaw) ?? .bus,
            directionDestinations: directionDestinations
        )
    }
}

// MARK: - Factory methods from value types

extension UserSavedStop {
    /// Create a UserSavedStop from a SingleStop (saved, not pinned)
    convenience init(from stop: SingleStop) {
        self.init(
            id: stop.id,
            stationId: stop.stationId,
            platformId: stop.platformId,
            routeId: stop.routeId,
            stopName: stop.stopName,
            transitTypeRaw: stop.transitType.rawValue,
            directionDestinations: stop.directionDestinations
        )
    }
}

extension UserPinnedStop {
    /// Create a UserPinnedStop from a PinnedStop (pinned with locked direction)
    convenience init(from stop: PinnedStop) {
        self.init(
            id: stop.id,
            stationId: stop.stationId,
            platformId: stop.platformId,
            routeId: stop.routeId,
            stopName: stop.stopName,
            transitTypeRaw: stop.transitType.rawValue,
            directionDestinations: stop.directionDestinations,
            pinnedDirectionId: stop.directionId
        )
    }
}

//
//  UserSavedStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import Foundation
import SwiftData

/// SwiftData model for persisting both saved and pinned stops.
/// - Saved stop: pinnedDirectionId is nil (direction is swipeable)
/// - Pinned stop: pinnedDirectionId is set (direction is locked)
@Model
final class UserSavedStop {
    @Attribute(.unique) var id: UUID
    var stationId: String
    var platformId: String
    var routeId: String
    var stopName: String
    var transitTypeRaw: String
    var directionDestinations: [String]
    var pinnedDirectionId: Int?
    var addedAt: Date

    var isPinned: Bool { pinnedDirectionId != nil }

    init(
        id: UUID = UUID(),
        stationId: String,
        platformId: String,
        routeId: String,
        stopName: String,
        transitTypeRaw: String,
        directionDestinations: [String] = [],
        pinnedDirectionId: Int? = nil,
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

    /// Convert a persisted pinned stop to a PinnedStop value type.
    /// Returns nil if this stop is not pinned.
    func toPinnedStop() -> PinnedStop? {
        guard let directionId = pinnedDirectionId else { return nil }
        return PinnedStop(
            id: id,
            stationId: stationId,
            platformId: platformId,
            routeId: routeId,
            directionId: directionId,
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
            directionDestinations: stop.directionDestinations,
            pinnedDirectionId: nil
        )
    }

    /// Create a UserSavedStop from a PinnedStop (pinned with locked direction)
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

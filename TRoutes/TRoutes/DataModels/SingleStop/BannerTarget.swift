//
//  BannerTarget.swift
//  TRoutes
//
//  Created by Adam Post on 8/19/26.
//

import Foundation

/// Wraps either a saved or pinned stop for use in StopBannerFeature.
/// Provides uniform access to common properties while preserving
/// the behavioral difference (swipeable vs direction-locked).
enum BannerTarget: Equatable, Identifiable {
    case saved(SingleStop)
    case pinned(PinnedStop)
    
    var id: UUID {
        switch self {
        case .saved(let stop): return stop.id
        case .pinned(let stop): return stop.id
        }
    }
    
    var stationId: String {
        switch self {
        case .saved(let stop): return stop.stationId
        case .pinned(let stop): return stop.stationId
        }
    }
    
    var platformId: String {
        switch self {
        case .saved(let stop): return stop.platformId
        case .pinned(let stop): return stop.platformId
        }
    }
    
    var routeId: String {
        switch self {
        case .saved(let stop): return stop.routeId
        case .pinned(let stop): return stop.routeId
        }
    }
    
    var stopName: String {
        switch self {
        case .saved(let stop): return stop.stopName
        case .pinned(let stop): return stop.stopName
        }
    }
    
    var transitType: TransitType {
        switch self {
        case .saved(let stop): return stop.transitType
        case .pinned(let stop): return stop.transitType
        }
    }
    
    var directionDestinations: [String] {
        switch self {
        case .saved(let stop): return stop.directionDestinations
        case .pinned(let stop): return stop.directionDestinations
        }
    }
    
    /// true when direction is locked (pinned stops), false when swipeable (saved stops)
    var isDirectionLocked: Bool {
        if case .pinned = self { return true }
        return false
    }
    
    /// Returns the locked direction for pinned stops, nil for saved stops
    var lockedDirectionId: Int? {
        if case .pinned(let stop) = self { return stop.directionId }
        return nil
    }
}

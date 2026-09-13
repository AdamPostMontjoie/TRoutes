//
//  TimingQueryPlan.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// An immutable description of the MBTA data needed to time one resolved route.
///
/// The ordered `legs` let one combined response be partitioned back into the
/// route's individual legs. Request filters and the coalescing key are derived
/// so they cannot disagree with those legs.
struct TimingQueryPlan: Equatable, Sendable {
    let resolvedRouteId: UUID
    let legs: [TimingLegPlan]

    var queriedStopIds: Set<String> {
        Set(legs.flatMap { leg in
            leg.origin.acceptableStopIds.union(leg.destination.acceptableStopIds)
        })
    }

    var services: Set<TimingRouteDirection> {
        Set(legs.flatMap(\.services))
    }

    var queriedRouteIds: Set<String> {
        Set(services.map(\.routeId))
    }

    var key: TimingQueryKey {
        TimingQueryKey(
            resolvedRouteId: resolvedRouteId,
            stopIds: queriedStopIds.sorted(),
            services: services.sorted()
        )
    }
}

/// Stable identity for route-timing request coalescing and schedule caching.
/// Arrays are stored in sorted order when the key is constructed.
struct TimingQueryKey: Hashable, Sendable {
    let resolvedRouteId: UUID
    let stopIds: [String]
    let services: [TimingRouteDirection]
}

/// A route and direction are paired because a route-wide response can contain
/// the same route in multiple directions.
struct TimingRouteDirection: Hashable, Sendable, Comparable {
    let routeId: String
    let directionId: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.routeId == rhs.routeId {
            return lhs.directionId < rhs.directionId
        }
        return lhs.routeId < rhs.routeId
    }
}

/// The filters and endpoint identities for one route leg.
struct TimingLegPlan: Equatable, Sendable, Identifiable {
    let id: UUID
    let services: Set<TimingRouteDirection>
    let origin: TimingEndpointPlan
    let destination: TimingEndpointPlan
}

/// One logical endpoint may be represented by several acceptable MBTA platform
/// or station IDs. `resolvedStopId` ties derived predictions back to JourneyState.
struct TimingEndpointPlan: Equatable, Sendable {
    let resolvedStopId: UUID
    let canonicalStopId: String
    let acceptableStopIds: Set<String>

    init(
        resolvedStopId: UUID,
        canonicalStopId: String,
        acceptableStopIds: Set<String>
    ) {
        self.resolvedStopId = resolvedStopId
        self.canonicalStopId = canonicalStopId
        self.acceptableStopIds = acceptableStopIds.union([canonicalStopId])
    }
}

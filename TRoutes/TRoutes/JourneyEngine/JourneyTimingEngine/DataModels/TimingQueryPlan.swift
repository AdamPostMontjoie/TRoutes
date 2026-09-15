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
    let predictionTargets: [TimingPredictionTargetPlan]

    init(
        resolvedRouteId: UUID,
        legs: [TimingLegPlan],
        predictionTargets: [TimingPredictionTargetPlan]? = nil
    ) {
        self.resolvedRouteId = resolvedRouteId
        self.legs = legs
        self.predictionTargets = predictionTargets ?? legs.map {
            TimingPredictionTargetPlan(
                endpoint: $0.origin,
                acceptableRouteDirections: $0.acceptableRouteDirections
            )
        }
    }

    var queriedStopIds: Set<String> {
        let legStopIds = Set(legs.flatMap { leg in
            leg.origin.acceptableStopIds.union(leg.destination.acceptableStopIds)
        })
        let predictionStopIds = Set(predictionTargets.flatMap {
            $0.endpoint.acceptableStopIds
        })
        return legStopIds.union(predictionStopIds)
    }

    var acceptableRouteDirections: Set<TimingRouteDirection> {
        Set(legs.flatMap(\.acceptableRouteDirections))
            .union(predictionTargets.flatMap(\.acceptableRouteDirections))
    }

    var queriedRouteIds: Set<String> {
        Set(acceptableRouteDirections.map(\.routeId))
    }

    var key: TimingQueryKey {
        TimingQueryKey(
            resolvedRouteId: resolvedRouteId,
            stopIds: queriedStopIds.sorted(),
            acceptableRouteDirections: acceptableRouteDirections.sorted()
        )
    }
}

/// Stable identity for route-timing request coalescing and schedule caching.
/// Arrays are stored in sorted order when the key is constructed.
struct TimingQueryKey: Hashable, Sendable {
    let resolvedRouteId: UUID
    let stopIds: [String]
    let acceptableRouteDirections: [TimingRouteDirection]
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
    let acceptableRouteDirections: Set<TimingRouteDirection>
    let origin: TimingEndpointPlan
    let destination: TimingEndpointPlan
}

/// One resolved stop whose prediction board should be projected from the
/// route-wide response.
struct TimingPredictionTargetPlan: Equatable, Sendable, Identifiable {
    let endpoint: TimingEndpointPlan
    let acceptableRouteDirections: Set<TimingRouteDirection>

    var id: UUID {
        endpoint.resolvedStopId
    }
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

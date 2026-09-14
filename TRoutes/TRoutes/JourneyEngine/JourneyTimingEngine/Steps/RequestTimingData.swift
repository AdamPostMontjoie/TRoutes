//
//  RequestTimingData.swift
//  TRoutes
//

import Foundation

// MARK: - Step 1: request all relevant information

extension JourneyTimingEngine {
    func remainingLegs(
        in route: ResolvedUserRoute,
        startingAt currentLegId: UUID
    ) throws -> [ResolvedLeg] {
        guard let currentLegIndex = route.legs.firstIndex(where: {
            $0.id == currentLegId
        }) else {
            throw JourneyTimingError.currentLegNotFound(currentLegId)
        }

        return Array(route.legs[currentLegIndex...])
    }

    func makeQueryPlan(
        route: ResolvedUserRoute,
        remainingLegs: [ResolvedLeg]
    ) -> TimingQueryPlan {
        let legs = remainingLegs.map { leg in
            let routeIds = Set(leg.acceptableRouteIds).union([leg.mbtaRouteId])
            let services = Set(routeIds.map { routeId in
                TimingRouteDirection(
                    routeId: routeId,
                    directionId: leg.mbtaDirectionId
                )
            })

            return TimingLegPlan(
                id: leg.id,
                services: services,
                origin: TimingEndpointPlan(
                    resolvedStopId: leg.startStop.id,
                    canonicalStopId: leg.startStop.mbtaStopId,
                    acceptableStopIds: Set(leg.startStop.acceptableStopIds)
                ),
                destination: TimingEndpointPlan(
                    resolvedStopId: leg.endStop.id,
                    canonicalStopId: leg.endStop.mbtaStopId,
                    acceptableStopIds: Set(leg.endStop.acceptableStopIds)
                )
            )
        }

        return TimingQueryPlan(resolvedRouteId: route.id, legs: legs)
    }

    /// PredictionManager owns the two network requests, request coalescing, and
    /// schedule cache. The two normalized result sets remain separate here.
    func requestAllTimingCalls(
        queryPlan: TimingQueryPlan
    ) async throws -> UnmergedTimingCalls {
        try await PredictionManager.shared.fetchTimingCalls(
            for: queryPlan,
            requestType: .currentStopPrediction
        )
    }
}

enum JourneyTimingError: Error, Equatable {
    case currentLegNotFound(UUID)
}

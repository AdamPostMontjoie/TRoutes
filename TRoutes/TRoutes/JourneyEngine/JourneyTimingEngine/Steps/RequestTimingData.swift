//
//  RequestTimingData.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

// MARK: - Step 1: request all relevant information

extension JourneyTimingEngine {
    func remainingLegs(in route: ResolvedUserRoute, startingAt currentLegId: UUID) throws -> [ResolvedLeg] {
        guard let currentLegIndex = route.legs.firstIndex(where: {
            $0.id == currentLegId
        }) else {
            throw JourneyTimingError.currentLegNotFound(currentLegId)
        }

        return Array(route.legs[currentLegIndex...])
    }

    func makeQueryPlan(route: ResolvedUserRoute, remainingLegs: [ResolvedLeg], additionalPredictionStopIds: Set<UUID> = []) -> TimingQueryPlan {
        let legs = remainingLegs.map { leg in
            return TimingLegPlan(
                id: leg.id,
                acceptableRouteDirections: acceptableRouteDirections(for: leg),
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

        var predictionTargets = legs.map { leg in
            TimingPredictionTargetPlan(
                endpoint: leg.origin,
                acceptableRouteDirections: leg.acceptableRouteDirections
            )
        }

        for stopId in additionalPredictionStopIds
        where !predictionTargets.contains(where: { $0.id == stopId }) {
            guard let stop = route.legs
                .flatMap(\.stops)
                .first(where: { $0.id == stopId }),
                  route.legs.indices.contains(stop.legIndex) else {
                continue
            }
            let leg = route.legs[stop.legIndex]
            predictionTargets.append(
                TimingPredictionTargetPlan(
                    endpoint: TimingEndpointPlan(
                        resolvedStopId: stop.id,
                        canonicalStopId: stop.mbtaStopId,
                        acceptableStopIds: Set(stop.acceptableStopIds)
                    ),
                    acceptableRouteDirections: acceptableRouteDirections(for: leg)
                )
            )
        }
        print("1/6 Created Timing Query Plan")
        return TimingQueryPlan(
            resolvedRouteId: route.id,
            legs: legs,
            predictionTargets: predictionTargets
        )
    }

    private func acceptableRouteDirections(for leg: ResolvedLeg) -> Set<TimingRouteDirection> {
        let routeIds = Set(leg.acceptableRouteIds).union([leg.mbtaRouteId])
        return Set(routeIds.map { routeId in
            TimingRouteDirection(
                routeId: routeId,
                directionId: leg.mbtaDirectionId
            )
        })
    }

    /// PredictionManager owns the two network requests, request coalescing, and
    /// schedule cache. The two normalized result sets remain separate here.
    func requestAllTimingCalls(queryPlan: TimingQueryPlan) async throws -> UnmergedTimingCalls {
        try await PredictionManager.shared.fetchTimingCalls(
            for: queryPlan,
            requestType: .currentStopPrediction
        )
    }
}

enum JourneyTimingError: Error, Equatable {
    case currentLegNotFound(UUID)
    case refreshInvalidated
}

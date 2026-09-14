//
//  JourneyTimingEngine.swift
//  TRoutes
//
//  Created by Adam Post on 9/12/26.
//

import Foundation

/// Owns timing refresh orchestration and ephemeral timing observations. Each
/// pipeline step lives in its own extension file so this actor reads as the
/// high-level route-timing algorithm rather than every implementation detail.
actor JourneyTimingEngine {
    static let shared = JourneyTimingEngine()
    private init() {}

    private var generation: UInt64 = 0
    private(set) var latestSnapshot: RouteTimingSnapshot?
    private var predictionHistory: RoutePredictionHistory?

    /// Runs the route-wide timing pipeline without mutating JourneyState.
    func refreshJourneyTiming(
        route: ResolvedUserRoute,
        context: JourneyTimingContext
    ) async throws -> JourneyTimingUpdate {
        generation &+= 1
        let refreshGeneration = generation
        let previousObservations = predictionHistory?.resolvedRouteId == route.id
            ? predictionHistory?.observations ?? [:]
            : [:]

        // Step 1: request all relevant route-wide information.
        let remainingLegs = try remainingLegs(
            in: route,
            startingAt: context.timingLegId
        )
        let queryPlan = makeQueryPlan(
            route: route,
            remainingLegs: remainingLegs
        )
        let unmergedCalls = try await requestAllTimingCalls(
            queryPlan: queryPlan
        )

        // Step 2: merge schedules, predictions, and disappearance history.
        let fetchedAt = Date()
        let currentMergedCalls = mergeScheduleAndPredictionCalls(unmergedCalls)
        let reconciliation = reconcilePredictionHistory(
            currentCalls: currentMergedCalls,
            previousObservations: previousObservations,
            queryPlan: queryPlan,
            context: context,
            now: fetchedAt
        )
        let mergedCalls = reconciliation.calls

        // Step 3: construct every valid same-trip option for every leg.
        let optionsByLeg = buildTripOptionsByLeg(
            queryPlan: queryPlan,
            mergedCalls: mergedCalls,
            context: context,
            now: fetchedAt
        )
        let coverageByLeg = buildCoverageByLeg(
            queryPlan: queryPlan,
            mergedCalls: mergedCalls,
            optionsByLeg: optionsByLeg
        )

        // Step 4: assess every adjacent-leg connection.
        let connectionGraph = connectAdjacentLegs(
            remainingLegs: remainingLegs,
            optionsByLeg: optionsByLeg
        )

        // Step 5: search every physically possible complete path.
        let completeJourneys = solveJourneys(
            remainingLegs: remainingLegs,
            optionsByLeg: optionsByLeg,
            connectionGraph: connectionGraph
        )

        // Step 6: apply phase-specific selection and project one timing update.
        let selection = selectTiming(
            context: context,
            queryPlan: queryPlan,
            completeJourneys: completeJourneys,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            connectionGraph: connectionGraph
        )
        let snapshot = makeSnapshot(
            queryPlan: queryPlan,
            context: context,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            mergedCalls: mergedCalls,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            selection: selection
        )

        // Only the newest overlapping refresh may replace actor-owned history.
        if refreshGeneration == generation {
            latestSnapshot = snapshot
            predictionHistory = RoutePredictionHistory(
                resolvedRouteId: route.id,
                observations: reconciliation.observations
            )
        }

        return makeTimingUpdate(
            route: route,
            context: context,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            queryPlan: queryPlan,
            mergedCalls: mergedCalls,
            selection: selection
        )
    }
}

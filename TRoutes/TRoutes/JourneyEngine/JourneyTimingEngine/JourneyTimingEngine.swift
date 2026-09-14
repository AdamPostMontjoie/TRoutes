//
//  JourneyTimingEngine.swift
//  TRoutes
//
//  Created by Adam Post on 9/12/26.
//

import CoreLocation
import Foundation

private struct OptionConnectionKey: Hashable {
    let arrivingOptionId: String
    let departingOptionId: String
}

private struct TimingConnectionGraph {
    let transfersByConnection: [OptionConnectionKey: TransferTiming]

    func transfer(
        from arrivingOption: LegTripOption,
        to departingOption: LegTripOption
    ) -> TransferTiming? {
        transfersByConnection[
            OptionConnectionKey(
                arrivingOptionId: arrivingOption.id,
                departingOptionId: departingOption.id
            )
        ]
    }
}

/// Stable identity for carrying a live observation across refreshes. The MBTA
/// schedule relationship is strongest; without it, stop sequence is required
/// so a trip that visits the same stop twice is never guessed together.
private enum TimingCallObservationKey: Hashable {
    case schedule(String)
    case tripStop(
        routeId: String,
        directionId: Int,
        tripId: String,
        stopId: String,
        stopSequence: Int
    )
}

private struct PredictionObservation {
    let lastLiveCall: StopCall
    let lastSeenAt: Date
    var missingSince: Date?
}

private struct RoutePredictionHistory {
    let resolvedRouteId: UUID
    let observations: [TimingCallObservationKey: PredictionObservation]
}

private struct PredictionHistoryReconciliation {
    let calls: [StopCall]
    let observations: [TimingCallObservationKey: PredictionObservation]
}

actor JourneyTimingEngine {
    static let shared = JourneyTimingEngine()
    private init() {}

    private var generation: UInt64 = 0
    private(set) var latestSnapshot: RouteTimingSnapshot?
    private var predictionHistory: RoutePredictionHistory?

    // MARK: - Refresh pipeline

    /// Runs the route-wide timing pipeline without mutating JourneyState.
    /// JourneyEngine will eventually validate and apply the returned update.
    func refreshJourneyTiming(
        route: ResolvedUserRoute,
        context: JourneyTimingContext
    ) async throws -> JourneyTimingUpdate {
        generation &+= 1
        let refreshGeneration = generation
        let previousObservations = predictionHistory?.resolvedRouteId == route.id
            ? predictionHistory?.observations ?? [:]
            : [:]

        // Step 1: describe and fetch the two route-wide result sets.
        let remainingLegs = try remainingLegs(
            in: route,
            startingAt: context.timingLegId
        )
        let queryPlan = makeQueryPlan(
            route: route,
            remainingLegs: remainingLegs
        )

        let unmergedCalls = try await requestAllTimingCalls(queryPlan: queryPlan)

        // Step 2: overlay predictions on their corresponding schedules.
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

        // Step 3: construct every usable same-trip option for every leg.
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

        // Step 4: connect feasible trip options on adjacent legs.
        let connectionGraph = connectAdjacentLegs(
            remainingLegs: remainingLegs,
            optionsByLeg: optionsByLeg
        )

        // Step 5: keep the best partial path reaching each option.
        let completeJourneys = solveJourneys(
            remainingLegs: remainingLegs,
            optionsByLeg: optionsByLeg,
            connectionGraph: connectionGraph
        )

        // Step 6: choose one complete journey using the product policy below.
        let recommendedJourney = selectRecommendedJourney(
            from: completeJourneys,
            coverageByLeg: coverageByLeg
        )

        let snapshot = makeSnapshot(
            queryPlan: queryPlan,
            context: context,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            mergedCalls: mergedCalls,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            recommendedJourney: recommendedJourney
        )
        if refreshGeneration == generation {
            latestSnapshot = snapshot
            predictionHistory = RoutePredictionHistory(
                resolvedRouteId: route.id,
                observations: reconciliation.observations
            )
        }

        return JourneyTimingUpdate(
            resolvedRouteId: route.id,
            context: context,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            predictionSlices: buildPredictionSlices(
                queryPlan: queryPlan,
                mergedCalls: mergedCalls,
                now: fetchedAt
            ),
            recommendedDeparture: context.isOnboard
                ? nil
                : recommendedJourney.map(makeRecommendedDeparture),
            currentLegArrival: recommendedJourney?.legs.first?.arrival,
            destinationArrival: recommendedJourney?.destinationArrival
        )
    }

    // MARK: - Step 1: request all relevant information

    private func remainingLegs(
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

    private func makeQueryPlan(
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
    private func requestAllTimingCalls(
        queryPlan: TimingQueryPlan
    ) async throws -> UnmergedTimingCalls {
        try await PredictionManager.shared.fetchTimingCalls(
            for: queryPlan,
            requestType: .currentStopPrediction
        )
    }

    // MARK: - Step 2: normalize and merge

    /// Produces one logical StopCall per trip/stop visit. A matching prediction
    /// adds live times without discarding the scheduled times used as fallback.
    private func mergeScheduleAndPredictionCalls(_ calls: UnmergedTimingCalls) -> [StopCall] {
        let schedulesById = Dictionary(
            calls.scheduleCalls.compactMap { call in
                call.scheduleId.map { ($0, call) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let schedulesByIdentity = Dictionary(
            calls.scheduleCalls.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var matchedScheduleKeys = Set<TripStopKey>()
        let predictedCalls = calls.predictionCalls.map { prediction in
            let schedule = prediction.scheduleId.flatMap { schedulesById[$0] }
                ?? schedulesByIdentity[prediction.key]

            if let schedule {
                matchedScheduleKeys.insert(schedule.key)
            }

            return makeMergedStopCall(
                schedule: schedule,
                prediction: prediction
            )
        }
        let scheduleOnlyCalls = calls.scheduleCalls.filter {
            !matchedScheduleKeys.contains($0.key)
        }

        return (predictedCalls + scheduleOnlyCalls).sorted {
            callSortTime($0) < callSortTime($1)
        }
    }

    private func makeMergedStopCall(schedule: StopCall?, prediction: StopCall) -> StopCall {
        guard let schedule else { return prediction }

        let availability: StopCallAvailability =
            isCanceledOrSkipped(prediction) || isCanceledOrSkipped(schedule)
            ? .canceled
            : .predicted

        return StopCall(
            key: prediction.key,
            routeId: prediction.routeId,
            directionId: prediction.directionId,
            vehicleId: prediction.vehicleId ?? schedule.vehicleId,
            headsign: prediction.headsign ?? schedule.headsign,
            isLastTrip: prediction.isLastTrip ?? schedule.isLastTrip,
            scheduleId: prediction.scheduleId ?? schedule.scheduleId,
            predictionId: prediction.predictionId,
            scheduled: schedule.scheduled,
            predicted: prediction.predicted,
            status: prediction.status ?? schedule.status,
            scheduleRelationship: prediction.scheduleRelationship
                ?? schedule.scheduleRelationship,
            availability: availability
        )
    }

    private func callSortTime(_ call: StopCall) -> Date {
        call.effectiveDeparture ?? call.effectiveArrival ?? .distantFuture
    }

    /// Reconciles a successful current response with previous live observations.
    /// This is intentionally separate from request caching: its only purpose is
    /// to interpret a prediction that was present and then disappeared.
    private func reconcilePredictionHistory(
        currentCalls: [StopCall],
        previousObservations: [TimingCallObservationKey: PredictionObservation],
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        now: Date
    ) -> PredictionHistoryReconciliation {
        var calls: [StopCall] = []
        var observations: [TimingCallObservationKey: PredictionObservation] = [:]
        var seenKeys = Set<TimingCallObservationKey>()

        for currentCall in currentCalls {
            guard let key = observationKey(for: currentCall) else {
                calls.append(normalizedAvailability(for: currentCall))
                continue
            }

            seenKeys.insert(key)

            if isCanceledOrSkipped(currentCall) {
                calls.append(copy(currentCall, availability: .canceled))
                continue
            }

            if currentCall.predicted != nil {
                let liveCall = copy(currentCall, availability: .predicted)
                calls.append(liveCall)
                observations[key] = PredictionObservation(
                    lastLiveCall: liveCall,
                    lastSeenAt: now,
                    missingSince: nil
                )
                continue
            }

            guard var observation = previousObservations[key] else {
                calls.append(currentCall)
                continue
            }

            if observation.missingSince == nil {
                observation.missingSince = now
            }
            guard shouldRetain(
                observation: observation,
                queryPlan: queryPlan,
                context: context,
                now: now
            ) else {
                calls.append(currentCall)
                continue
            }
            observations[key] = observation
            if let reconciledCall = callForMissingPrediction(
                scheduleCall: currentCall,
                observation: observation,
                queryPlan: queryPlan,
                context: context,
                now: now
            ) {
                calls.append(reconciledCall)
            }
        }

        for (key, previousObservation) in previousObservations
        where !seenKeys.contains(key)
            && isRelevant(previousObservation.lastLiveCall, to: queryPlan) {
            var observation = previousObservation
            if observation.missingSince == nil {
                observation.missingSince = now
            }
            guard shouldRetain(
                observation: observation,
                queryPlan: queryPlan,
                context: context,
                now: now
            ) else {
                continue
            }

            observations[key] = observation
            if let reconciledCall = callForMissingPrediction(
                scheduleCall: nil,
                observation: observation,
                queryPlan: queryPlan,
                context: context,
                now: now
            ) {
                calls.append(reconciledCall)
            }
        }

        return PredictionHistoryReconciliation(
            calls: calls.sorted { callSortTime($0) < callSortTime($1) },
            observations: observations
        )
    }

    private func observationKey(for call: StopCall) -> TimingCallObservationKey? {
        if let scheduleId = call.scheduleId {
            return .schedule(scheduleId)
        }
        guard let stopSequence = call.key.stopSequence else {
            return nil
        }
        return .tripStop(
            routeId: call.routeId,
            directionId: call.directionId,
            tripId: call.key.tripId,
            stopId: call.key.stopId,
            stopSequence: stopSequence
        )
    }

    private func normalizedAvailability(for call: StopCall) -> StopCall {
        if isCanceledOrSkipped(call) {
            return copy(call, availability: .canceled)
        }
        return call
    }

    private func callForMissingPrediction(
        scheduleCall: StopCall?,
        observation: PredictionObservation,
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        now: Date
    ) -> StopCall? {
        let lastLiveCall = observation.lastLiveCall
        let lastPredictedEvent = predictionEventTime(for: lastLiveCall)

        if let lastPredictedEvent, lastPredictedEvent <= now {
            return historicalOverlay(
                scheduleCall: scheduleCall,
                liveCall: lastLiveCall,
                availability: .departed
            )
        }

        // MARK: - Policy decision: prediction-disappearance grace
        // Thirty seconds spans two normal refresh intervals. Measure elapsed
        // time rather than refresh count because manual refreshes are faster.
        let predictionLossGrace: TimeInterval = 30
        let missingDuration = now.timeIntervalSince(
            observation.missingSince ?? now
        )
        if missingDuration <= predictionLossGrace {
            return historicalOverlay(
                scheduleCall: scheduleCall,
                liveCall: lastLiveCall,
                availability: .predictionLost
            )
        }

        if let scheduleCall {
            return scheduleCall
        }

        // A confirmed onboard trip keeps its scheduled destination fallback
        // even if that schedule was omitted from the latest response.
        if isOnboardDestination(
            lastLiveCall,
            queryPlan: queryPlan,
            context: context
        ) {
            return scheduleFallback(from: lastLiveCall)
        }

        return nil
    }

    private func historicalOverlay(
        scheduleCall: StopCall?,
        liveCall: StopCall,
        availability: StopCallAvailability
    ) -> StopCall {
        let merged = scheduleCall.map {
            makeMergedStopCall(schedule: $0, prediction: liveCall)
        } ?? liveCall
        return copy(merged, availability: availability)
    }

    private func scheduleFallback(from call: StopCall) -> StopCall? {
        guard call.scheduled != nil else { return nil }
        return StopCall(
            key: call.key,
            routeId: call.routeId,
            directionId: call.directionId,
            vehicleId: call.vehicleId,
            headsign: call.headsign,
            isLastTrip: call.isLastTrip,
            scheduleId: call.scheduleId,
            predictionId: nil,
            scheduled: call.scheduled,
            predicted: nil,
            status: call.status,
            scheduleRelationship: call.scheduleRelationship,
            availability: .scheduledOnly
        )
    }

    private func copy(
        _ call: StopCall,
        availability: StopCallAvailability
    ) -> StopCall {
        StopCall(
            key: call.key,
            routeId: call.routeId,
            directionId: call.directionId,
            vehicleId: call.vehicleId,
            headsign: call.headsign,
            isLastTrip: call.isLastTrip,
            scheduleId: call.scheduleId,
            predictionId: call.predictionId,
            scheduled: call.scheduled,
            predicted: call.predicted,
            status: call.status,
            scheduleRelationship: call.scheduleRelationship,
            availability: availability
        )
    }

    private func predictionEventTime(for call: StopCall) -> Date? {
        call.predicted?.departure ?? call.predicted?.arrival
    }

    private func shouldRetain(
        observation: PredictionObservation,
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        now: Date
    ) -> Bool {
        if isOnboardCurrentLegCall(
            observation.lastLiveCall,
            queryPlan: queryPlan,
            context: context
        ) {
            return true
        }

        // MARK: - Policy decision: prediction-history retention
        // Tombstones only need to outlive the event long enough to prevent a
        // cached schedule from resurrecting it.
        let retentionAfterEvent: TimeInterval = 10 * 60
        let liveCall = observation.lastLiveCall
        let eventTime = [
            predictionEventTime(for: liveCall),
            liveCall.scheduled?.departure ?? liveCall.scheduled?.arrival,
            observation.lastSeenAt
        ]
            .compactMap { $0 }
            .max() ?? observation.lastSeenAt
        return now.timeIntervalSince(eventTime) <= retentionAfterEvent
    }

    private func isRelevant(
        _ call: StopCall,
        to queryPlan: TimingQueryPlan
    ) -> Bool {
        queryPlan.queriedStopIds.contains(call.key.stopId)
            && queryPlan.services.contains(
                TimingRouteDirection(
                    routeId: call.routeId,
                    directionId: call.directionId
                )
            )
    }

    private func isOnboardDestination(
        _ call: StopCall,
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext
    ) -> Bool {
        guard case let .onboard(tripId) = context.phase,
              let tripId,
              call.key.tripId == tripId,
              let currentLeg = queryPlan.legs.first,
              currentLeg.id == context.timingLegId else {
            return false
        }
        return currentLeg.destination.acceptableStopIds.contains(call.key.stopId)
    }

    private func isOnboardCurrentLegCall(
        _ call: StopCall,
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext
    ) -> Bool {
        guard case let .onboard(tripId) = context.phase,
              let tripId,
              call.key.tripId == tripId,
              let currentLeg = queryPlan.legs.first,
              currentLeg.id == context.timingLegId else {
            return false
        }
        return currentLeg.origin.acceptableStopIds.contains(call.key.stopId)
            || currentLeg.destination.acceptableStopIds.contains(call.key.stopId)
    }

    // MARK: - Step 3: construct options for every leg

    private func buildTripOptionsByLeg(
        queryPlan: TimingQueryPlan,
        mergedCalls: [StopCall],
        context: JourneyTimingContext,
        now: Date
    ) -> [UUID: [LegTripOption]] {
        Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
            let isInProgressLeg = context.isOnboard
                && leg.id == context.timingLegId
            let options = buildTripOptions(
                for: leg,
                from: mergedCalls,
                isInProgressLeg: isInProgressLeg,
                onboardTripId: isInProgressLeg ? context.onboardTripId : nil,
                now: now
            )
            return (leg.id, options)
        })
    }

    /// The complete option-building algorithm in one place: filter both
    /// endpoints, group destinations by trip, pair same-trip calls, reject
    /// invalid pairs, and return the remaining options chronologically.
    private func buildTripOptions(
        for leg: TimingLegPlan,
        from calls: [StopCall],
        isInProgressLeg: Bool,
        onboardTripId: String?,
        now: Date
    ) -> [LegTripOption] {
        if isInProgressLeg && onboardTripId == nil {
            // Journey progression proves the passenger is onboard, but without
            // a trip identity selecting another trip would be a guess.
            return []
        }

        var originCalls = matchingCalls(
            at: leg.origin,
            services: leg.services,
            from: calls
        )
        var destinationCalls = matchingCalls(
            at: leg.destination,
            services: leg.services,
            from: calls
        )
        if let onboardTripId {
            originCalls = originCalls.filter { $0.key.tripId == onboardTripId }
            destinationCalls = destinationCalls.filter {
                $0.key.tripId == onboardTripId
            }
        }
        let destinationsByTrip = Dictionary(
            grouping: destinationCalls,
            by: { $0.key.tripId }
        )

        var optionsById: [String: LegTripOption] = [:]
        for origin in originCalls {
            for destination in destinationsByTrip[origin.key.tripId] ?? [] {
                guard let option = makeLegTripOption(
                    for: leg,
                    origin: origin,
                    destination: destination,
                    isInProgressLeg: isInProgressLeg,
                    now: now
                ) else {
                    continue
                }
                if optionsById[option.id] == nil {
                    optionsById[option.id] = option
                }
            }
        }

        return optionsById.values.sorted { $0.departure < $1.departure }
    }

    private func matchingCalls(
        at endpoint: TimingEndpointPlan,
        services: Set<TimingRouteDirection>,
        from calls: [StopCall]
    ) -> [StopCall] {
        calls.filter { call in
            endpoint.acceptableStopIds.contains(call.key.stopId)
                && services.contains(
                    TimingRouteDirection(
                        routeId: call.routeId,
                        directionId: call.directionId
                    )
                )
        }
    }

    private func makeLegTripOption(
        for leg: TimingLegPlan,
        origin: StopCall,
        destination: StopCall,
        isInProgressLeg: Bool,
        now: Date
    ) -> LegTripOption? {
        guard (isInProgressLeg
               ? isUsableCompletedOrigin(origin)
               : isUsableForTravel(origin)),
              isUsableForTravel(destination),
              origin.key.tripId == destination.key.tripId,
              origin.routeId == destination.routeId,
              origin.directionId == destination.directionId,
              let departure = origin.effectiveDeparture,
              isInProgressLeg || departure >= now,
              destination.effectiveArrival != nil else {
            return nil
        }

        if let originSequence = origin.key.stopSequence,
           let destinationSequence = destination.key.stopSequence,
           destinationSequence <= originSequence {
            return nil
        }

        return LegTripOption(
            legId: leg.id,
            origin: origin,
            destination: destination
        )
    }

    private func isUsableForTravel(_ call: StopCall) -> Bool {
        switch call.availability {
        case .canceled, .departed:
            return false
        case .predicted, .predictionLost, .scheduledOnly:
            return !isCanceledOrSkipped(call)
        }
    }

    private func isUsableCompletedOrigin(_ call: StopCall) -> Bool {
        call.availability != .canceled && !isCanceledOrSkipped(call)
    }

    private func isCanceledOrSkipped(_ call: StopCall) -> Bool {
        [call.status, call.scheduleRelationship]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.contains("canceled")
                    || value.contains("cancelled")
                    || value.contains("skipped")
            }
    }

    // MARK: - Step 4: connect adjacent legs

    private func connectAdjacentLegs(
        remainingLegs: [ResolvedLeg],
        optionsByLeg: [UUID: [LegTripOption]]
    ) -> TimingConnectionGraph {
        guard remainingLegs.count > 1 else {
            return TimingConnectionGraph(transfersByConnection: [:])
        }

        var transfersByConnection: [OptionConnectionKey: TransferTiming] = [:]

        for legIndex in 0..<(remainingLegs.count - 1) {
            let arrivingLeg = remainingLegs[legIndex]
            let departingLeg = remainingLegs[legIndex + 1]
            let arrivingOptions = optionsByLeg[arrivingLeg.id] ?? []
            let departingOptions = optionsByLeg[departingLeg.id] ?? []

            for (optionIndex, departingOption) in departingOptions.enumerated() {
                let nextAlternativeDeparture = nextAlternativeDeparture(
                    after: optionIndex,
                    in: departingOptions
                )
                let nextAlternativeGap = nextAlternativeDeparture.map {
                    $0.timeIntervalSince(departingOption.departure)
                }
                let isLastService = departingOption.origin.isLastTrip == true
                    && nextAlternativeDeparture == nil
                let safetyMargin = safetyMargin(
                    for: departingLeg,
                    nextAlternativeGap: nextAlternativeGap,
                    isLastService: isLastService
                )
                let requirement = calculateTransferTime(
                    from: arrivingLeg,
                    to: departingLeg,
                    safetyMargin: safetyMargin
                )

                for arrivingOption in arrivingOptions {
                    let transfer = TransferTiming(
                        arrivingLegId: arrivingLeg.id,
                        departingLegId: departingLeg.id,
                        stationId: departingLeg.startStop.stationId,
                        arrival: arrivingOption.arrival,
                        departure: departingOption.departure,
                        requirement: requirement,
                        nextAlternativeDeparture: nextAlternativeDeparture,
                        risk: connectionRisk(
                            usableSlack: departingOption.departure
                                .timeIntervalSince(arrivingOption.arrival)
                                - requirement.requiredTime,
                            nextAlternativeGap: nextAlternativeGap,
                            isLastService: isLastService
                        )
                    )

                    guard transfer.usableSlack >= 0 else { continue }

                    transfersByConnection[
                        OptionConnectionKey(
                            arrivingOptionId: arrivingOption.id,
                            departingOptionId: departingOption.id
                        )
                    ] = transfer
                }
            }
        }

        return TimingConnectionGraph(
            transfersByConnection: transfersByConnection
        )
    }

    private func nextAlternativeDeparture(
        after optionIndex: Int,
        in options: [LegTripOption]
    ) -> Date? {
        let selectedDeparture = options[optionIndex].departure
        return options.dropFirst(optionIndex + 1)
            .first { $0.departure > selectedDeparture }?
            .departure
    }

    // MARK: - Step 5: search complete paths

    /// Dynamic programming keeps one best path for each option on the current
    /// layer. Future compatibility depends only on that final option.
    private func solveJourneys(
        remainingLegs: [ResolvedLeg],
        optionsByLeg: [UUID: [LegTripOption]],
        connectionGraph: TimingConnectionGraph
    ) -> [TimedJourney] {
        guard let firstLeg = remainingLegs.first else { return [] }

        var bestPathByFinalOptionId: [String: TimedJourney] = [:]
        for option in optionsByLeg[firstLeg.id] ?? [] {
            if let path = TimedJourney(
                legs: [option],
                transfers: [],
                warnings: []
            ) {
                bestPathByFinalOptionId[option.id] = path
            }
        }

        for leg in remainingLegs.dropFirst() {
            var nextBestPathByFinalOptionId: [String: TimedJourney] = [:]

            for option in optionsByLeg[leg.id] ?? [] {
                for path in bestPathByFinalOptionId.values {
                    guard let previousOption = path.legs.last,
                          let transfer = connectionGraph.transfer(
                            from: previousOption,
                            to: option
                          ),
                          let candidate = TimedJourney(
                            legs: path.legs + [option],
                            transfers: path.transfers + [transfer],
                            warnings: []
                          ) else {
                        continue
                    }

                    if let current = nextBestPathByFinalOptionId[option.id] {
                        if isPreferredJourney(candidate, over: current) {
                            nextBestPathByFinalOptionId[option.id] = candidate
                        }
                    } else {
                        nextBestPathByFinalOptionId[option.id] = candidate
                    }
                }
            }

            bestPathByFinalOptionId = nextBestPathByFinalOptionId
            if bestPathByFinalOptionId.isEmpty {
                return []
            }
        }

        return Array(bestPathByFinalOptionId.values)
    }

    // MARK: - Step 6: select and describe the recommendation

    private func selectRecommendedJourney(
        from journeys: [TimedJourney],
        coverageByLeg: [UUID: LegTimingCoverage]
    ) -> TimedJourney? {
        guard let selected = journeys.min(by: { candidate, current in
            isPreferredJourney(candidate, over: current)
        }) else {
            return nil
        }

        return TimedJourney(
            legs: selected.legs,
            transfers: selected.transfers,
            warnings: timingWarnings(
                for: selected,
                coverageByLeg: coverageByLeg
            )
        )
    }

    private func makeRecommendedDeparture(
        from journey: TimedJourney
    ) -> RecommendedDeparture {
        RecommendedDeparture(
            departureTime: journey.originDeparture,
            timeSource: journey.legs[0].departureTimeSource,
            destinationArrivalTime: journey.destinationArrival,
            selectedTripIds: journey.legs.map(\.tripId),
            confidence: journey.confidence,
            warnings: journey.warnings
        )
    }

    private func timingWarnings(
        for journey: TimedJourney,
        coverageByLeg: [UUID: LegTimingCoverage]
    ) -> [TimingWarning] {
        var warnings: [TimingWarning] = []

        for option in journey.legs {
            if option.confidence == .scheduled {
                appendWarning(.scheduleOnly(legId: option.legId), to: &warnings)
            }

            if option.origin.availability == .predictionLost
                || option.destination.availability == .predictionLost {
                appendWarning(
                    .predictionTemporarilyUnavailable(legId: option.legId),
                    to: &warnings
                )
            }

            if coverageByLeg[option.legId]?.status != .sufficient {
                appendWarning(
                    .incompleteCoverage(legId: option.legId),
                    to: &warnings
                )
            }
        }

        for transfer in journey.transfers {
            switch transfer.risk {
            case .normal:
                break
            case .tight:
                appendWarning(
                    .tightConnection(stationId: transfer.stationId),
                    to: &warnings
                )
            case .highConsequence:
                if let nextAlternativeDeparture = transfer.nextAlternativeDeparture {
                    appendWarning(
                        .longRecoveryGap(
                            stationId: transfer.stationId,
                            seconds: nextAlternativeDeparture
                                .timeIntervalSince(transfer.departure)
                        ),
                        to: &warnings
                    )
                }
            case .lastService:
                appendWarning(
                    .lastService(stationId: transfer.stationId),
                    to: &warnings
                )
            }
        }

        return warnings
    }

    private func appendWarning(
        _ warning: TimingWarning,
        to warnings: inout [TimingWarning]
    ) {
        if !warnings.contains(warning) {
            warnings.append(warning)
        }
    }

    // MARK: - Policy decision: transfer safety and risk

    /// These are deliberately basic first-pass values. Revisit the mode-based
    /// margins, recovery-gap thresholds, and walking model with real route data.
    private func safetyMargin(
        for departingLeg: ResolvedLeg,
        nextAlternativeGap: TimeInterval?,
        isLastService: Bool
    ) -> TimeInterval {
        let ordinaryMargin: TimeInterval = 2 * 60
        let infrequentServiceMargin: TimeInterval = 5 * 60
        let highConsequenceMargin: TimeInterval = 10 * 60

        let modeMargin: TimeInterval
        switch departingLeg.transitType {
        case .commuterRail, .ferry:
            modeMargin = infrequentServiceMargin
        default:
            modeMargin = ordinaryMargin
        }

        if isLastService || (nextAlternativeGap ?? 0) >= 60 * 60 {
            return max(modeMargin, highConsequenceMargin)
        }
        if (nextAlternativeGap ?? 0) >= 30 * 60 {
            return max(modeMargin, infrequentServiceMargin)
        }
        return modeMargin
    }

    private func calculateTransferTime(
        from arrivingLeg: ResolvedLeg,
        to departingLeg: ResolvedLeg,
        safetyMargin: TimeInterval
    ) -> TransferRequirement {
        let arrivalLocation = CLLocation(
            latitude: arrivingLeg.endStop.latitude,
            longitude: arrivingLeg.endStop.longitude
        )
        let departureLocation = CLLocation(
            latitude: departingLeg.startStop.latitude,
            longitude: departingLeg.startStop.longitude
        )
        let walkingDistance = arrivalLocation.distance(from: departureLocation)

        return TransferRequirement(
            minimumTransferTime: walkingDistance / 1.4,
            safetyMargin: safetyMargin
        )
    }

    private func connectionRisk(
        usableSlack: TimeInterval,
        nextAlternativeGap: TimeInterval?,
        isLastService: Bool
    ) -> ConnectionRisk {
        if isLastService {
            return .lastService
        }
        if (nextAlternativeGap ?? 0) >= 30 * 60 {
            return .highConsequence
        }
        if usableSlack < 2 * 60 {
            return .tight
        }
        return .normal
    }

    // MARK: - Policy decision: journey ranking

    /// Current ordering: earliest destination arrival, lowest total connection
    /// risk, then latest initial departure. The final signature is only a stable
    /// deterministic tie-breaker.
    private func isPreferredJourney(
        _ candidate: TimedJourney,
        over current: TimedJourney
    ) -> Bool {
        if candidate.destinationArrival != current.destinationArrival {
            return candidate.destinationArrival < current.destinationArrival
        }

        let candidateRisk = totalRiskScore(candidate)
        let currentRisk = totalRiskScore(current)
        if candidateRisk != currentRisk {
            return candidateRisk < currentRisk
        }

        if candidate.originDeparture != current.originDeparture {
            return candidate.originDeparture > current.originDeparture
        }

        return journeySignature(candidate) < journeySignature(current)
    }

    private func totalRiskScore(_ journey: TimedJourney) -> Int {
        journey.transfers.reduce(into: 0) { score, transfer in
            switch transfer.risk {
            case .normal:
                break
            case .tight:
                score += 1
            case .highConsequence:
                score += 2
            case .lastService:
                score += 3
            }
        }
    }

    private func journeySignature(_ journey: TimedJourney) -> String {
        journey.legs.map(\.id).joined(separator: "|")
    }

    // MARK: - Prediction-state projection

    private func buildPredictionSlices(
        queryPlan: TimingQueryPlan,
        mergedCalls: [StopCall],
        now: Date
    ) -> [PredictionSlice] {
        queryPlan.legs.map { leg in
            createPredictionSlice(for: leg, calls: mergedCalls, now: now)
        }
    }

    /// Pulls the first three boardable calls for one resolved boarding stop.
    /// The slice ID is the exact ID later matched to PredictionState.
    private func createPredictionSlice(
        for leg: TimingLegPlan,
        calls: [StopCall],
        now: Date
    ) -> PredictionSlice {
        let sortedCalls = matchingCalls(
            at: leg.origin,
            services: leg.services,
            from: calls
        )
            .filter { isUsableForTravel($0) }
            .filter { ($0.effectiveDeparture ?? .distantPast) >= now }
            .sorted { callSortTime($0) < callSortTime($1) }

        var seenTripIds = Set<String>()
        var predictions: [TransitPrediction] = []
        for call in sortedCalls {
            guard seenTripIds.insert(call.key.tripId).inserted,
                  let prediction = makeTransitPrediction(from: call, now: now) else {
                continue
            }
            predictions.append(prediction)
            if predictions.count == 3 {
                break
            }
        }

        return PredictionSlice(
            predictedStopId: leg.origin.resolvedStopId,
            predictions: predictions
        )
    }

    private func makeTransitPrediction(from call: StopCall, now: Date) -> TransitPrediction? {
        guard let predictionId = call.predictionId ?? call.scheduleId else {
            return nil
        }

        let times = call.predicted ?? call.scheduled
        let display: String
        if let status = call.status, !status.isEmpty {
            display = status
        } else if call.predicted != nil {
            let isBoarding = times?.arrival.map { $0 < now } == true
                && times?.departure.map { $0 >= now } == true
            if isBoarding {
                display = "Boarding"
            } else if let eventTime = times?.arrival ?? times?.departure {
                let minutes = Calendar.current.dateComponents(
                    [.minute],
                    from: now,
                    to: eventTime
                ).minute ?? 0
                display = minutes <= 0 ? "Arriving" : "\(minutes) min"
            } else {
                return nil
            }
        } else if let eventTime = times?.departure ?? times?.arrival {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            display = formatter.string(from: eventTime)
        } else {
            return nil
        }

        return TransitPrediction(
            display: display,
            arrivalDate: times?.arrival,
            departureDate: times?.departure,
            vehicleId: call.vehicleId,
            predictionId: predictionId,
            tripId: call.key.tripId,
            stopId: call.key.stopId,
            routeId: call.routeId,
            headsign: call.headsign,
            directionId: call.directionId,
            stopSequence: call.key.stopSequence
        )
    }

    // MARK: - Coverage and snapshot construction

    private func buildCoverageByLeg(
        queryPlan: TimingQueryPlan,
        mergedCalls: [StopCall],
        optionsByLeg: [UUID: [LegTripOption]]
    ) -> [UUID: LegTimingCoverage] {
        Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
            let originCalls = matchingCalls(
                at: leg.origin,
                services: leg.services,
                from: mergedCalls
            ).filter { isUsableForTravel($0) }
            let destinationCalls = matchingCalls(
                at: leg.destination,
                services: leg.services,
                from: mergedCalls
            ).filter { isUsableForTravel($0) }
            let options = optionsByLeg[leg.id] ?? []

            let status: TimingCoverageStatus
            if originCalls.isEmpty && destinationCalls.isEmpty {
                status = .unavailable
            } else if options.isEmpty {
                status = .insufficient
            } else {
                status = .sufficient
            }

            let coverage = LegTimingCoverage(
                legId: leg.id,
                originCoveredThrough: originCalls.compactMap(\.effectiveDeparture).max(),
                destinationCoveredThrough: destinationCalls.compactMap(\.effectiveArrival).max(),
                completeTripOptionCount: options.count,
                status: status
            )
            return (leg.id, coverage)
        })
    }

    private func makeSnapshot(
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        generation: UInt64,
        fetchedAt: Date,
        mergedCalls: [StopCall],
        optionsByLeg: [UUID: [LegTripOption]],
        coverageByLeg: [UUID: LegTimingCoverage],
        recommendedJourney: TimedJourney?
    ) -> RouteTimingSnapshot {
        let callsByKey = Dictionary(
            mergedCalls.map { ($0.key, $0) },
            uniquingKeysWith: { current, replacement in
                replacement.predicted == nil ? current : replacement
            }
        )

        return RouteTimingSnapshot(
            resolvedRouteId: queryPlan.resolvedRouteId,
            context: context,
            generation: generation,
            fetchedAt: fetchedAt,
            calls: callsByKey,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            recommendedJourney: recommendedJourney
        )
    }
}

enum JourneyTimingError: Error, Equatable {
    case currentLegNotFound(UUID)
}

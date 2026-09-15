//
//  MergeTimingData.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Stable identity for carrying a live observation across refreshes. The MBTA
/// schedule relationship is strongest; without it, stop sequence is required
/// so a trip that visits the same stop twice is never guessed together.
enum TimingCallObservationKey: Hashable {
    case schedule(String)
    case tripStop(
        routeId: String,
        directionId: Int,
        tripId: String,
        stopId: String,
        stopSequence: Int
    )
}

struct PredictionObservation {
    let lastLiveCall: TripStopTiming
    let lastSeenAt: Date
    var missingSince: Date?
}

struct RoutePredictionHistory {
    let resolvedRouteId: UUID
    let observations: [TimingCallObservationKey: PredictionObservation]
}

struct PredictionHistoryReconciliation {
    let calls: [TripStopTiming]
    let observations: [TimingCallObservationKey: PredictionObservation]
}

// MARK: - Step 2: normalize and merge

extension JourneyTimingEngine {
    /// Merges prediction and schedule timing for each trip and stop.
    func mergeScheduleAndPredictionCalls(
        _ calls: UnmergedTimingCalls
    ) -> [TripStopTiming] {
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

    func makeMergedStopCall(
        schedule: TripStopTiming?,
        prediction: TripStopTiming
    ) -> TripStopTiming {
        guard let schedule else { return prediction }

        let availability: StopCallAvailability =
            isCanceledOrSkipped(prediction) || isCanceledOrSkipped(schedule)
            ? .canceled
            : .predicted

        return TripStopTiming(
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

    func callSortTime(_ call: TripStopTiming) -> Date {
        call.effectiveDeparture ?? call.effectiveArrival ?? .distantFuture
    }

    /// Reconciles a successful current response with previous live observations.
    /// This is intentionally separate from request caching: its only purpose is
    /// to interpret a prediction that was present and then disappeared.
    func reconcilePredictionHistory(
        currentCalls: [TripStopTiming],
        previousObservations: [TimingCallObservationKey: PredictionObservation],
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        now: Date
    ) -> PredictionHistoryReconciliation {
        var calls: [TripStopTiming] = []
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
                now: now
            ) {
                calls.append(reconciledCall)
            }
        }

        print("2/6 Merged Timing Calls")
        return PredictionHistoryReconciliation(
            calls: calls.sorted { callSortTime($0) < callSortTime($1) },
            observations: observations
        )
    }

    func observationKey(for call: TripStopTiming) -> TimingCallObservationKey? {
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

    func normalizedAvailability(for call: TripStopTiming) -> TripStopTiming {
        if isCanceledOrSkipped(call) {
            return copy(call, availability: .canceled)
        }
        return call
    }

    func callForMissingPrediction(
        scheduleCall: TripStopTiming?,
        observation: PredictionObservation,
        now: Date
    ) -> TripStopTiming? {
        let lastLiveCall = observation.lastLiveCall
        let lastPredictedEvent = predictionEventTime(for: lastLiveCall)

        if let lastPredictedEvent, lastPredictedEvent <= now {
            return historicalOverlay(
                scheduleCall: scheduleCall,
                liveCall: lastLiveCall,
                availability: .departed
            )
        }

        let historyPolicy = PredictionHistoryPolicy()
        let missingDuration = now.timeIntervalSince(
            observation.missingSince ?? now
        )
        if missingDuration <= historyPolicy.predictionLossGrace {
            return historicalOverlay(
                scheduleCall: scheduleCall,
                liveCall: lastLiveCall,
                availability: .predictionLost
            )
        }

        return scheduleCall
    }

    func historicalOverlay(
        scheduleCall: TripStopTiming?,
        liveCall: TripStopTiming,
        availability: StopCallAvailability
    ) -> TripStopTiming {
        let merged = scheduleCall.map {
            makeMergedStopCall(schedule: $0, prediction: liveCall)
        } ?? liveCall
        return copy(merged, availability: availability)
    }

    func copy(
        _ call: TripStopTiming,
        availability: StopCallAvailability
    ) -> TripStopTiming {
        TripStopTiming(
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

    func predictionEventTime(for call: TripStopTiming) -> Date? {
        call.predicted?.departure ?? call.predicted?.arrival
    }

    func shouldRetain(
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

        let historyPolicy = PredictionHistoryPolicy()
        let liveCall = observation.lastLiveCall
        let eventTime = [
            predictionEventTime(for: liveCall),
            liveCall.scheduled?.departure ?? liveCall.scheduled?.arrival,
            observation.lastSeenAt
        ]
            .compactMap { $0 }
            .max() ?? observation.lastSeenAt
        return now.timeIntervalSince(eventTime)
            <= historyPolicy.retentionAfterEvent
    }

    func isRelevant(
        _ call: TripStopTiming,
        to queryPlan: TimingQueryPlan
    ) -> Bool {
        queryPlan.queriedStopIds.contains(call.key.stopId)
            && queryPlan.acceptableRouteDirections.contains(
                TimingRouteDirection(
                    routeId: call.routeId,
                    directionId: call.directionId
                )
            )
    }

    func isOnboardCurrentLegCall(
        _ call: TripStopTiming,
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
}

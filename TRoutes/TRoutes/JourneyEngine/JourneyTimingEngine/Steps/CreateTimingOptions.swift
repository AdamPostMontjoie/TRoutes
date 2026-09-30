//
//  CreateTimingOptions.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

// MARK: - Step 3: construct options for every leg

extension JourneyTimingEngine {
    func retainingConfirmedOnboardOrigin(in calls: [TripStopTiming], previousOptions: [LegTripOption], leg: TimingLegPlan, tripId: String) -> [TripStopTiming] {
        guard let origin = previousOptions.first(where: { $0.tripId == tripId })?.origin,
              !matchingCalls(
                at: leg.origin,
                acceptableRouteDirections: leg.acceptableRouteDirections,
                from: [origin]
              ).isEmpty,
              !matchingCalls(
                at: leg.origin,
                acceptableRouteDirections: leg.acceptableRouteDirections,
                from: calls
              ).contains(where: { $0.key.tripId == tripId }) else {
            return calls
        }
        return calls + [origin]
    }

    func buildTripOptionsByLeg(queryPlan: TimingQueryPlan, mergedCalls: [TripStopTiming], currentPredictionCalls: [TripStopTiming], context: JourneyTimingContext, now: Date) -> [UUID: [LegTripOption]] {
        let optionsByLeg = Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
            let isInProgressLeg = context.isOnboard
                && leg.id == context.timingLegId
            let options = buildTripOptions(
                for: leg,
                from: mergedCalls,
                currentPredictionCalls: currentPredictionCalls,
                isInProgressLeg: isInProgressLeg,
                onboardTripId: isInProgressLeg ? context.onboardTripId : nil,
                now: now
            )
            return (leg.id, options)
        })
        print("3/6 Created Timing Options")
        return optionsByLeg
    }

    /// Filters both endpoints, groups destinations by trip, pairs same-trip
    /// calls, rejects invalid pairs, and returns valid options chronologically.
    func buildTripOptions(for leg: TimingLegPlan, from calls: [TripStopTiming], currentPredictionCalls: [TripStopTiming], isInProgressLeg: Bool, onboardTripId: String?, now: Date) -> [LegTripOption] {
        if isInProgressLeg && onboardTripId == nil {
            // Journey progression proves the passenger is onboard, but without
            // a trip identity selecting another trip would be a guess.
            return []
        }

        var originCalls = matchingCalls(
            at: leg.origin,
            acceptableRouteDirections: leg.acceptableRouteDirections,
            from: calls
        )
        var destinationCalls = matchingCalls(
            at: leg.destination,
            acceptableRouteDirections: leg.acceptableRouteDirections,
            from: calls
        )
        if let onboardTripId {
            originCalls = originCalls.filter { $0.key.tripId == onboardTripId }
            destinationCalls = destinationCalls.filter {
                $0.key.tripId == onboardTripId
            }
        }
        if !isInProgressLeg {
            originCalls = filterScheduledBoardingCalls(
                originCalls,
                currentPredictions: matchingCalls(
                    at: leg.origin,
                    acceptableRouteDirections: leg.acceptableRouteDirections,
                    from: currentPredictionCalls
                )
            )
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

    /// Callers scope both inputs to the same boarding stop and allowed services.
    /// Predictions replace their trip's schedule and cover every service through
    /// the last predicted boarding time; later schedules remain usable.
    func filterScheduledBoardingCalls(_ calls: [TripStopTiming], currentPredictions: [TripStopTiming]) -> [TripStopTiming] {
        let predictedTripIds = Set(currentPredictions.map(\.key.tripId))
        let lastPredictedBoardingTime = currentPredictions
            .filter { isUsableForTravel($0) }
            .compactMap { $0.predicted?.arrival ?? $0.predicted?.departure }
            .max()

        return calls.filter { call in
            guard let boardingTime = call.selectedBoardingTime,
                  boardingTime.source == .schedule else { return true }
            guard !predictedTripIds.contains(call.key.tripId) else { return false }
            guard let lastPredictedBoardingTime else { return true }
            return boardingTime.time > lastPredictedBoardingTime
        }
    }

    func matchingCalls(at endpoint: TimingEndpointPlan, acceptableRouteDirections: Set<TimingRouteDirection>, from calls: [TripStopTiming]) -> [TripStopTiming] {
        calls.filter { call in
            endpoint.acceptableStopIds.contains(call.key.stopId)
                && acceptableRouteDirections.contains(
                    TimingRouteDirection(
                        routeId: call.routeId,
                        directionId: call.directionId
                    )
                )
        }
    }

    func makeLegTripOption(for leg: TimingLegPlan, origin: TripStopTiming, destination: TripStopTiming, isInProgressLeg: Bool, now: Date) -> LegTripOption? {
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

    func isUsableForTravel(_ call: TripStopTiming) -> Bool {
        switch call.availability {
        case .canceled, .departed:
            return false
        case .predicted, .predictionLost, .scheduledOnly:
            return !isCanceledOrSkipped(call)
        }
    }

    func isUsableCompletedOrigin(_ call: TripStopTiming) -> Bool {
        call.availability != .canceled && !isCanceledOrSkipped(call)
    }

    func isCanceledOrSkipped(_ call: TripStopTiming) -> Bool {
        [call.status, call.scheduleRelationship]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.contains("canceled")
                    || value.contains("cancelled")
                    || value.contains("skipped")
            }
    }
}

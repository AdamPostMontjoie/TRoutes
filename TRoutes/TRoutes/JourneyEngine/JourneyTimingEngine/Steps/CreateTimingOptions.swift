//
//  CreateTimingOptions.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

// MARK: - Step 3: construct options for every leg

extension JourneyTimingEngine {
    func buildTripOptionsByLeg(queryPlan: TimingQueryPlan, mergedCalls: [TripStopTiming], context: JourneyTimingContext, now: Date) -> [UUID: [LegTripOption]] {
        let optionsByLeg = Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
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
        print("3/6 Created Timing Options")
        return optionsByLeg
    }

    /// Filters both endpoints, groups destinations by trip, pairs same-trip
    /// calls, rejects invalid pairs, and returns valid options chronologically.
    func buildTripOptions(for leg: TimingLegPlan, from calls: [TripStopTiming], isInProgressLeg: Bool, onboardTripId: String?, now: Date) -> [LegTripOption] {
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

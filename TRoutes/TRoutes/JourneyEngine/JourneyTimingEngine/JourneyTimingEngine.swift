//
//  JourneyTimingEngine.swift
//  TRoutes
//
//  Created by Adam Post on 9/12/26.
//

import CoreLocation
import Foundation

actor JourneyTimingEngine {
    static let shared = JourneyTimingEngine()
    private init() {}

    private var generation: UInt64 = 0
    private(set) var latestSnapshot: RouteTimingSnapshot?

    // MARK: - Refresh pipeline

    /// Runs the route-wide timing pipeline without mutating JourneyState.
    /// JourneyEngine will eventually validate and apply the returned update.
    func refreshJourneyTiming(
        route: ResolvedUserRoute,
        currentLegId: UUID
    ) async throws -> JourneyTimingUpdate {
        generation &+= 1
        let refreshGeneration = generation

        // Step 1: describe and fetch the two route-wide result sets.
        let queryPlan = try makeQueryPlan(
            route: route,
            currentLegId: currentLegId
        )

        let unmergedCalls = try await requestAllTimingCalls(queryPlan: queryPlan)

        // Step 2: overlay predictions on their corresponding schedules.
        let mergedCalls = mergeScheduleAndPredictionCalls(unmergedCalls)

        // Step 3: construct every usable same-trip option for every leg.
        let fetchedAt = Date()
        let optionsByLeg = buildTripOptionsByLeg(
            queryPlan: queryPlan,
            mergedCalls: mergedCalls,
            now: fetchedAt
        )
        let coverageByLeg = buildCoverageByLeg(
            queryPlan: queryPlan,
            mergedCalls: mergedCalls,
            optionsByLeg: optionsByLeg
        )

        let snapshot = makeSnapshot(
            queryPlan: queryPlan,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            mergedCalls: mergedCalls,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg
        )
        if refreshGeneration == generation {
            latestSnapshot = snapshot
        }

        return JourneyTimingUpdate(
            resolvedRouteId: route.id,
            generation: refreshGeneration,
            fetchedAt: fetchedAt,
            predictionSlices: buildPredictionSlices(
                queryPlan: queryPlan,
                mergedCalls: mergedCalls,
                now: fetchedAt
            ),
            recommendedDeparture: nil,
            currentLegArrival: nil,
            destinationArrival: nil
        )
    }

    // MARK: - Step 1: request all relevant information

    private func makeQueryPlan(
        route: ResolvedUserRoute,
        currentLegId: UUID
    ) throws -> TimingQueryPlan {
        guard let currentLegIndex = route.legs.firstIndex(where: {
            $0.id == currentLegId
        }) else {
            throw JourneyTimingError.currentLegNotFound(currentLegId)
        }

        let remainingLegs = route.legs[currentLegIndex...]
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
            isCanceled(prediction) || isCanceled(schedule) ? .canceled : .predicted

        return StopCall(
            key: prediction.key,
            routeId: prediction.routeId,
            directionId: prediction.directionId,
            vehicleId: prediction.vehicleId ?? schedule.vehicleId,
            headsign: prediction.headsign ?? schedule.headsign,
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

    // MARK: - Step 3: construct options for every leg

    private func buildTripOptionsByLeg(
        queryPlan: TimingQueryPlan,
        mergedCalls: [StopCall],
        now: Date
    ) -> [UUID: [LegTripOption]] {
        Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
            let options = buildTripOptions(
                for: leg,
                from: mergedCalls,
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
        now: Date
    ) -> [LegTripOption] {
        let originCalls = matchingCalls(
            at: leg.origin,
            services: leg.services,
            from: calls
        )
        let destinationCalls = matchingCalls(
            at: leg.destination,
            services: leg.services,
            from: calls
        )
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
        now: Date
    ) -> LegTripOption? {
        guard isUsableForTravel(origin),
              isUsableForTravel(destination),
              origin.key.tripId == destination.key.tripId,
              origin.routeId == destination.routeId,
              origin.directionId == destination.directionId,
              let departure = origin.effectiveDeparture,
              departure >= now,
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
        case .canceled, .departed, .predictionLost:
            return false
        case .predicted, .scheduledOnly:
            return !isCanceled(call)
        }
    }

    private func isCanceled(_ call: StopCall) -> Bool {
        [call.status, call.scheduleRelationship]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.contains("canceled") || value.contains("cancelled")
            }
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
        generation: UInt64,
        fetchedAt: Date,
        mergedCalls: [StopCall],
        optionsByLeg: [UUID: [LegTripOption]],
        coverageByLeg: [UUID: LegTimingCoverage]
    ) -> RouteTimingSnapshot {
        let callsByKey = Dictionary(
            mergedCalls.map { ($0.key, $0) },
            uniquingKeysWith: { current, replacement in
                replacement.predicted == nil ? current : replacement
            }
        )

        return RouteTimingSnapshot(
            resolvedRouteId: queryPlan.resolvedRouteId,
            generation: generation,
            fetchedAt: fetchedAt,
            calls: callsByKey,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            recommendedJourney: nil
        )
    }

    // MARK: - Step 4 preparation: transfer policy

    /// Temporary physical transfer estimate. The later connection policy should
    /// pass a risk-based safety margin instead of always using 30 seconds.
    private func calculateTransferTime(
        from arrivingLeg: ResolvedLeg,
        to departingLeg: ResolvedLeg,
        safetyMargin: TimeInterval = 30
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
    // Steps 4-6 remain: connect adjacent options, search complete paths, and
    // apply the product's risk/earliness policy before creating the command.
}

enum JourneyTimingError: Error, Equatable {
    case currentLegNotFound(UUID)
}

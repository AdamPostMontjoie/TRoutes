//
//  CreateTimingUpdate.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

struct JourneyTimingSelection {
    let etaJourney: TimedJourney?
    let recommendedJourney: TimedJourney?
    let currentLegOption: LegTripOption?
    let monitoredConnection: JourneyConnectionTiming?
}

// MARK: - Step 6: select and project timing state

extension JourneyTimingEngine {
    /// Selects recommendation and ETA independently from the same candidate
    /// journeys. Before the first stop they are the same journey. Afterwards,
    /// ETA is anchored to the user's first boardable or confirmed trip.
    func selectTiming(context: JourneyTimingContext, queryPlan: TimingQueryPlan, completeJourneys: [TimedJourney], optionsByLeg: [UUID: [LegTripOption]], coverageByLeg: [UUID: LegTimingCoverage], connectionGraph: TimingConnectionGraph) -> JourneyTimingSelection {
        let selectionPolicy = JourneySelectionPolicy()
        let recommendedJourney = context.allowsRecommendation
            ? selectRecommendedJourney(
                from: completeJourneys,
                coverageByLeg: coverageByLeg,
                selectionPolicy: selectionPolicy
            )
            : nil

        let firstLegOptions = queryPlan.legs.first.flatMap {
            optionsByLeg[$0.id]
        } ?? []
        if context.allowsRecommendation {
            logRecommendedPath(
                recommendedJourney,
                firstLegOptions: firstLegOptions
            )
        }
        let currentLegOption: LegTripOption?
        if context.allowsRecommendation {
            currentLegOption = recommendedJourney?.legs.first
        } else {
            currentLegOption = firstLegOptions.min {
                $0.departure < $1.departure
            }
        }

        let etaJourney: TimedJourney?
        if context.allowsRecommendation {
            etaJourney = recommendedJourney
        } else if let currentLegOption {
            let anchoredJourneys = completeJourneys.filter {
                $0.legs.first?.id == currentLegOption.id
            }
            etaJourney = selectionPolicy.selectActualJourney(
                from: anchoredJourneys
            )
        } else {
            etaJourney = nil
        }

        let monitoredConnection = context.showsConnectionWarning
            ? makeMonitoredConnection(
                currentLegOption: currentLegOption,
                queryPlan: queryPlan,
                optionsByLeg: optionsByLeg,
                connectionGraph: connectionGraph
            )
            : nil

        return JourneyTimingSelection(
            etaJourney: etaJourney,
            recommendedJourney: recommendedJourney,
            currentLegOption: currentLegOption,
            monitoredConnection: monitoredConnection
        )
    }

    private func logRecommendedPath(_ journey: TimedJourney?, firstLegOptions: [LegTripOption]) {
        guard let journey else {
            print("Recommended path: unavailable (no complete journey)")
            return
        }

        let recommendedTime = journey.originDeparture.formatted(
            date: .omitted,
            time: .shortened
        )
        let firstUsableTime = firstLegOptions.map(\.departure).min()
        let firstTimeText = firstUsableTime?.formatted(
            date: .omitted,
            time: .shortened
        ) ?? "nil"
        let deltaText = firstUsableTime.map {
            String(
                format: "%+.1f min",
                journey.originDeparture.timeIntervalSince($0) / 60
            )
        } ?? "nil"
        let source = journey.legs[0].departureTimeSource == .prediction
            ? "predicted"
            : "scheduled"
        let trips = journey.legs.map(\.tripId).joined(separator: " → ")

        print(
            "Recommended path: \(recommendedTime) | first usable: \(firstTimeText) | delta: \(deltaText) | \(source) | trips: \(trips)"
        )
    }

    func selectRecommendedJourney(from journeys: [TimedJourney], coverageByLeg: [UUID: LegTimingCoverage], selectionPolicy: JourneySelectionPolicy) -> TimedJourney? {
        guard let selected = selectionPolicy.selectRecommendation(
            from: journeys
        ) else {
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

    /// The watched connection is the earliest upcoming service on the next leg
    /// for the user's assumed current trip. It may be physically impossible;
    /// retaining it is what lets a likely-miss warning change on later refreshes.
    func makeMonitoredConnection(currentLegOption: LegTripOption?, queryPlan: TimingQueryPlan, optionsByLeg: [UUID: [LegTripOption]], connectionGraph: TimingConnectionGraph) -> JourneyConnectionTiming? {
        guard let currentLegOption,
              queryPlan.legs.count > 1 else {
            return nil
        }

        let nextLeg = queryPlan.legs[1]
        let nextOptions = (optionsByLeg[nextLeg.id] ?? []).sorted {
            $0.departure < $1.departure
        }
        for option in nextOptions {
            if let connection = connectionGraph.connection(
                from: currentLegOption,
                to: option
            ) {
                return makeJourneyConnectionTiming(
                    from: connection,
                    arrivingOption: currentLegOption,
                    departingOption: option
                )
            }
        }
        return nil
    }

    func makeRecommendedDeparture(from journey: TimedJourney) -> RecommendedDeparture {
        let firstLeg = journey.legs[0]
        return RecommendedDeparture(
            resolvedLegId: firstLeg.legId,
            tripId: firstLeg.tripId,
            departureTime: firstLeg.departure,
            timeSource: firstLeg.departureTimeSource
        )
    }

    func makeJourneyLegTiming(from option: LegTripOption) -> JourneyLegTiming {
        JourneyLegTiming(
            resolvedLegId: option.legId,
            tripId: option.tripId,
            routeId: option.routeId,
            directionId: option.origin.directionId,
            originStopId: option.origin.key.stopId,
            destinationStopId: option.destination.key.stopId,
            departure: option.departure,
            arrival: option.arrival,
            departureSource: option.departureTimeSource,
            arrivalSource: option.arrivalTimeSource
        )
    }

    func makeJourneyConnectionTiming(from connection: TransferTiming, arrivingOption: LegTripOption, departingOption: LegTripOption) -> JourneyConnectionTiming {
        JourneyConnectionTiming(
            arrivingLegId: connection.arrivingLegId,
            arrivingTripId: arrivingOption.tripId,
            departingLegId: connection.departingLegId,
            departingTripId: departingOption.tripId,
            stationId: connection.stationId,
            arrivingStopId: arrivingOption.destination.key.stopId,
            departingStopId: departingOption.origin.key.stopId,
            arrival: connection.arrival,
            departure: connection.departure,
            minimumTransferDuration: connection.requirement.minimumTransferTime,
            preferredReliabilityBuffer: connection.requirement.preferredReliabilityBuffer,
            nextAlternativeDeparture: connection.nextAlternativeDeparture,
            isHighConsequence: connection.isHighConsequence,
            isLastService: connection.isLastService,
            warning: connection.warning
        )
    }

    func makeJourneyTimingItinerary(from journey: TimedJourney) -> JourneyTimingItinerary {
        let connections = journey.transfers.enumerated().map { index, connection in
            makeJourneyConnectionTiming(
                from: connection,
                arrivingOption: journey.legs[index],
                departingOption: journey.legs[index + 1]
            )
        }
        return JourneyTimingItinerary(
            legs: journey.legs.map(makeJourneyLegTiming),
            connections: connections
        )
    }

    func makeJourneyTimingPlan(from selection: JourneyTimingSelection, context: JourneyTimingContext) -> JourneyTimingPlan {
        JourneyTimingPlan(
            status: timingStatus(for: selection),
            selectedItinerary: selection.etaJourney.map(makeJourneyTimingItinerary),
            currentLeg: context.allowsRecommendation
                ? nil
                : selection.currentLegOption.map(makeJourneyLegTiming),
            recommendedDeparture: selection.recommendedJourney.map(makeRecommendedDeparture),
            monitoredConnection: selection.monitoredConnection
        )
    }

    func makeTimingUpdate(route: ResolvedUserRoute, context: JourneyTimingContext, refreshSessionId: UUID, generation: UInt64, fetchedAt: Date, predictionSlices: [PredictionSlice], selection: JourneyTimingSelection) -> JourneyTimingUpdate {
        let update = JourneyTimingUpdate(
            resolvedRouteId: route.id,
            context: context,
            refreshSessionId: refreshSessionId,
            generation: generation,
            fetchedAt: fetchedAt,
            predictionSlices: predictionSlices,
            timing: makeJourneyTimingPlan(
                from: selection,
                context: context
            )
        )
        print("6/6 Created Timing Update")
        return update
    }

    func timingStatus(for selection: JourneyTimingSelection) -> JourneyTimingStatus {
        guard let etaJourney = selection.etaJourney else {
            return .unavailable
        }

        let usesTemporarilyUnavailablePrediction = etaJourney.legs.contains {
            $0.origin.availability == .predictionLost
                || $0.destination.availability == .predictionLost
        }
        return usesTemporarilyUnavailablePrediction ? .stale : .current
    }

    func timingWarnings(for journey: TimedJourney, coverageByLeg: [UUID: LegTimingCoverage]) -> [TimingWarning] {
        var warnings: [TimingWarning] = []

        for option in journey.legs {
            if option.sourceComposition == .scheduled {
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
            switch transfer.warning {
            case .none:
                break
            case .tight:
                appendWarning(
                    .tightConnection(stationId: transfer.stationId),
                    to: &warnings
                )
            case .highConsequence:
                appendConsequenceWarning(for: transfer, to: &warnings)
            case .tightHighConsequence:
                appendWarning(
                    .tightConnection(stationId: transfer.stationId),
                    to: &warnings
                )
                appendConsequenceWarning(for: transfer, to: &warnings)
            case .likelyMiss:
                // Complete TimedJourney values cannot contain impossible edges.
                break
            }
        }

        return warnings
    }

    func appendConsequenceWarning(for transfer: TransferTiming, to warnings: inout [TimingWarning]) {
        if transfer.isLastService {
            appendWarning(
                .lastService(stationId: transfer.stationId),
                to: &warnings
            )
        } else if let nextAlternativeDeparture =
                    transfer.nextAlternativeDeparture {
            appendWarning(
                .longRecoveryGap(
                    stationId: transfer.stationId,
                    seconds: nextAlternativeDeparture.timeIntervalSince(
                        transfer.departure
                    )
                ),
                to: &warnings
            )
        }
    }

    func appendWarning(_ warning: TimingWarning, to warnings: inout [TimingWarning]) {
        if !warnings.contains(warning) {
            warnings.append(warning)
        }
    }

    // MARK: - Existing prediction-state projection

    func buildPredictionSlices(queryPlan: TimingQueryPlan, rawCalls: UnmergedTimingCalls, now: Date) -> [PredictionSlice] {
        queryPlan.predictionTargets.map { target in
            createPredictionSlice(for: target, rawCalls: rawCalls, now: now)
        }
    }

    /// Takes current live calls first, then fills the remaining board slots with
    /// distinct scheduled calls. ETA and recommendations use the merged calls,
    /// never this display-only projection.
    /// The slice ID is the exact ID later matched to PredictionState.
    func createPredictionSlice(for target: TimingPredictionTargetPlan, rawCalls: UnmergedTimingCalls, now: Date) -> PredictionSlice {
        let matchingLiveCalls = matchingCalls(
            at: target.endpoint,
            acceptableRouteDirections: target.acceptableRouteDirections,
            from: rawCalls.predictionCalls
        )
        // A current prediction for a trip supersedes its schedule even if that
        // prediction is canceled or no longer boardable.
        let predictedTripIds = Set(matchingLiveCalls.map(\.key.tripId))
        let sortedLiveCalls = matchingLiveCalls
            .filter { $0.predictionId != nil && $0.predicted != nil }
            .filter { isUsableForTravel($0) }
            .filter { ($0.effectiveDeparture ?? .distantPast) >= now }
            .sorted { callSortTime($0) < callSortTime($1) }
        let sortedScheduleCalls = matchingCalls(
            at: target.endpoint,
            acceptableRouteDirections: target.acceptableRouteDirections,
            from: rawCalls.scheduleCalls
        )
            .filter { $0.scheduleId != nil && $0.scheduled != nil }
            .filter { isUsableForTravel($0) }
            .filter { ($0.effectiveDeparture ?? .distantPast) >= now }
            .filter { !predictedTripIds.contains($0.key.tripId) }
            .sorted { callSortTime($0) < callSortTime($1) }

        var observedLiveTripIds = Set<String>()
        var observedLiveCalls: [(call: TripStopTiming, prediction: TransitPrediction)] = []
        for call in sortedLiveCalls {
            guard observedLiveTripIds.insert(call.key.tripId).inserted,
                  let prediction = makeTransitPrediction(
                    from: call,
                    now: now
                  ) else {
                continue
            }
            observedLiveCalls.append((call, prediction))
        }
        // The board is capped at three, but arrival detection must see every
        // live trip so moving from fourth to third cannot look like a departure.
        var selectedCalls = Array(observedLiveCalls.prefix(3))
        var seenTripIds = Set(selectedCalls.map { $0.call.key.tripId })
        if selectedCalls.count < 3 {
            for call in sortedScheduleCalls {
                guard seenTripIds.insert(call.key.tripId).inserted,
                      let prediction = makeTransitPrediction(
                        from: call,
                        now: now
                      ) else {
                    continue
                }
                selectedCalls.append((call, prediction))
                if selectedCalls.count == 3 {
                    break
                }
            }
        }

        return PredictionSlice(
            predictedStopId: target.id,
            displayPredictions: selectedCalls
                .sorted { callSortTime($0.call) < callSortTime($1.call) }
                .map { $0.prediction },
            livePredictions: observedLiveCalls.map { $0.prediction }
        )
    }

    func makeTransitPrediction(from call: TripStopTiming, now: Date) -> TransitPrediction? {
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

    // MARK: - Coverage and snapshot projection

    func buildCoverageByLeg(queryPlan: TimingQueryPlan, mergedCalls: [TripStopTiming], optionsByLeg: [UUID: [LegTripOption]]) -> [UUID: LegTimingCoverage] {
        Dictionary(uniqueKeysWithValues: queryPlan.legs.map { leg in
            let originCalls = matchingCalls(
                at: leg.origin,
                acceptableRouteDirections: leg.acceptableRouteDirections,
                from: mergedCalls
            ).filter { isUsableForTravel($0) }
            let destinationCalls = matchingCalls(
                at: leg.destination,
                acceptableRouteDirections: leg.acceptableRouteDirections,
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
                originCoveredThrough: originCalls
                    .compactMap(\.effectiveDeparture)
                    .max(),
                destinationCoveredThrough: destinationCalls
                    .compactMap(\.effectiveArrival)
                    .max(),
                completeTripOptionCount: options.count,
                status: status
            )
            return (leg.id, coverage)
        })
    }

    func makeSnapshot(queryPlan: TimingQueryPlan, context: JourneyTimingContext, generation: UInt64, fetchedAt: Date, mergedCalls: [TripStopTiming], optionsByLeg: [UUID: [LegTripOption]], coverageByLeg: [UUID: LegTimingCoverage], selection: JourneyTimingSelection) -> RouteTimingSnapshot {
        let timingsByTripStop = Dictionary(
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
            timingsByTripStop: timingsByTripStop,
            optionsByLeg: optionsByLeg,
            coverageByLeg: coverageByLeg,
            etaJourney: selection.etaJourney,
            recommendedJourney: selection.recommendedJourney,
            monitoredConnection: selection.monitoredConnection
        )
    }
}

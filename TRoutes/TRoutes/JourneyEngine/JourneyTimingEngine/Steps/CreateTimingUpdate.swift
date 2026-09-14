//
//  CreateTimingUpdate.swift
//  TRoutes
//

import Foundation

struct JourneyTimingSelection {
    let etaJourney: TimedJourney?
    let recommendedJourney: TimedJourney?
    let currentLegOption: LegTripOption?
    let connection: TransferTiming?
}

// MARK: - Step 6: select and project timing state

extension JourneyTimingEngine {
    /// Selects recommendation and ETA independently from the same candidate
    /// journeys. Before the first stop they are the same journey. Afterwards,
    /// ETA is anchored to the user's first boardable or confirmed trip.
    func selectTiming(
        context: JourneyTimingContext,
        queryPlan: TimingQueryPlan,
        completeJourneys: [TimedJourney],
        optionsByLeg: [UUID: [LegTripOption]],
        coverageByLeg: [UUID: LegTimingCoverage],
        connectionGraph: TimingConnectionGraph
    ) -> JourneyTimingSelection {
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

        let connection = context.showsConnectionWarning
            ? watchedConnection(
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
            connection: connection
        )
    }

    func selectRecommendedJourney(
        from journeys: [TimedJourney],
        coverageByLeg: [UUID: LegTimingCoverage],
        selectionPolicy: JourneySelectionPolicy
    ) -> TimedJourney? {
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
    func watchedConnection(
        currentLegOption: LegTripOption?,
        queryPlan: TimingQueryPlan,
        optionsByLeg: [UUID: [LegTripOption]],
        connectionGraph: TimingConnectionGraph
    ) -> TransferTiming? {
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
                return connection
            }
        }
        return nil
    }

    func makeRecommendedDeparture(
        from journey: TimedJourney
    ) -> RecommendedDeparture {
        RecommendedDeparture(
            departureTime: journey.originDeparture,
            timeSource: journey.legs[0].departureTimeSource,
            destinationArrivalTime: journey.destinationArrival,
            selectedTripIds: journey.legs.map(\.tripId),
            confidence: journey.confidence
        )
    }

    func makeTimingUpdate(
        route: ResolvedUserRoute,
        context: JourneyTimingContext,
        generation: UInt64,
        fetchedAt: Date,
        queryPlan: TimingQueryPlan,
        mergedCalls: [StopCall],
        selection: JourneyTimingSelection
    ) -> JourneyTimingUpdate {
        JourneyTimingUpdate(
            resolvedRouteId: route.id,
            context: context,
            generation: generation,
            fetchedAt: fetchedAt,
            status: timingStatus(for: selection),
            predictionSlices: buildPredictionSlices(
                queryPlan: queryPlan,
                mergedCalls: mergedCalls,
                now: fetchedAt
            ),
            recommendedDeparture: selection.recommendedJourney.map(
                makeRecommendedDeparture
            ),
            currentLegArrival: context.allowsRecommendation
                ? nil
                : selection.currentLegOption?.arrival,
            destinationArrival: selection.etaJourney?.destinationArrival,
            connection: selection.connection
        )
    }

    func timingStatus(
        for selection: JourneyTimingSelection
    ) -> JourneyTimingStatus {
        guard let etaJourney = selection.etaJourney else {
            return .unavailable
        }

        let usesTemporarilyUnavailablePrediction = etaJourney.legs.contains {
            $0.origin.availability == .predictionLost
                || $0.destination.availability == .predictionLost
        }
        return usesTemporarilyUnavailablePrediction ? .stale : .current
    }

    func timingWarnings(
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

    func appendConsequenceWarning(
        for transfer: TransferTiming,
        to warnings: inout [TimingWarning]
    ) {
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

    func appendWarning(
        _ warning: TimingWarning,
        to warnings: inout [TimingWarning]
    ) {
        if !warnings.contains(warning) {
            warnings.append(warning)
        }
    }

    // MARK: - Existing prediction-state projection

    func buildPredictionSlices(
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
    func createPredictionSlice(
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
                  let prediction = makeTransitPrediction(
                    from: call,
                    now: now
                  ) else {
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

    func makeTransitPrediction(
        from call: StopCall,
        now: Date
    ) -> TransitPrediction? {
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

    func buildCoverageByLeg(
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

    func makeSnapshot(
        queryPlan: TimingQueryPlan,
        context: JourneyTimingContext,
        generation: UInt64,
        fetchedAt: Date,
        mergedCalls: [StopCall],
        optionsByLeg: [UUID: [LegTripOption]],
        coverageByLeg: [UUID: LegTimingCoverage],
        selection: JourneyTimingSelection
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
            etaJourney: selection.etaJourney,
            recommendedJourney: selection.recommendedJourney,
            connection: selection.connection
        )
    }
}

//
//  JourneyAction.swift
//  TRoutes
//
//  Created by Adam Post on 6/19/26.
//

///Determines what we need to do after receiving a JourneyCommand based on JourneyState
enum JourneyAction: Equatable {
    case arriveAtStop
    case departFromStop
    case backtrackToStop
    case handleJourneyTimingUpdate
    case evaluateTimingRefresh
    
    func reduce(state: inout JourneyState, timingUpdate: JourneyTimingUpdate? = nil, isManual: Bool = false) -> [JourneyEffect] {
        switch self {
        case .arriveAtStop:
            return arriveAtStop(state: &state)
        case .departFromStop:
            return departFromStop(state: &state)
        case .backtrackToStop:
            return backtrackToStop(state: &state)
        case .handleJourneyTimingUpdate:
            return handleJourneyTimingUpdate(
                state: &state,
                update: timingUpdate
            )
        case .evaluateTimingRefresh:
            return evaluateTimingRefresh(state: &state, isManual: isManual)
        }
    }
    
    private func arriveAtStop(state: inout JourneyState) -> [JourneyEffect] {
        guard let stop = state.currentStop else {
            return []
        }
        
        state.pendingDepartureConfirmation = false
        state.movementStatus = .atStop
        
        switch stop.journeyRole {
        case .boarding:
            state.activeLegPrediction = PredictionState(
                predictedStop: stop,
                predictedStopType: .boarding,
                acceptableRouteIds: state.acceptableRouteIds(for: stop),
                loadingState: .loading(stopId: stop.mbtaStopId)
            )
            //clears recommendation
            var effects: [JourneyEffect] = [.updateJourneyTiming]
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            if let nextStop = state.nextStop {
                if state.monitoringMode == .surface && nextStop.monitoringMode == .underground {
                    state.monitoringMode = .underground
                    effects.append(.switchMonitoringMode(.underground))
                }
                effects.append(.monitorStop(stop))
            }
            effects.append(.sendDebugNotification("entered \(stop.stopName)"))
            return effects
            
        case let .transfer(overlapsNext):
            guard overlapsNext else {
                state.activeLegPrediction = nil
                state.transferLegPrediction = nil
                return [
                    // .updateJourneyTiming,
                    .sendDebugNotification("entered \(stop.stopName)")
                ]
            }

            let transferNotice = state.timingState.timing.flatMap {
                BoardingNoticeDetails(
                    recommendation: nil,
                    timingPlan: $0,
                    legs: state.legOrder
                )
            }
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.movementStatus = .atStop
            state.activeLegPrediction = PredictionState(
                predictedStop: nextStop,
                predictedStopType: .boarding,
                acceptableRouteIds: state.acceptableRouteIds(for: nextStop),
                loadingState: .loading(stopId: nextStop.mbtaStopId)
            )
            state.transferLegPrediction = nil
            var effects = effectsForNextStop(
                nextStop,
                state: state,
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "transfered to \(nextStop.stopName)"
            )
            if let transferNotice {
                effects.append(.createNotification(intent: .transferNow(transferNotice)))
            }
            return effects
            
        case .intermediate:
            state.activeLegPrediction = nil
            state.transferLegPrediction = nil
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            var effects: [JourneyEffect] = []
            if let nextStop = state.nextStop {
                if state.monitoringMode == .surface && nextStop.monitoringMode == .underground {
                    state.monitoringMode = .underground
                    effects.append(.switchMonitoringMode(.underground))
                }
                effects.append(.monitorStop(stop))
            }
//            if state.timingContext != nil {
//                effects.append(.updateJourneyTiming)
//            }
            effects.append(.sendDebugNotification("entered \(stop.stopName)"))
            return effects
            
        case .final:
            return [
                .scheduleEndRoute(seconds: 60),
                .sendDebugNotification("entered \(stop.stopName)"),
                .createNotification(intent: .arrivedAtDestination(stop.stopName))
            ]
        }
    }
    
    private func departFromStop(state: inout JourneyState) -> [JourneyEffect] {
        guard let stop = state.currentStop else {
            return []
        }
        
        state.movementStatus = .enRoute
        
        switch stop.journeyRole {
        case .boarding:
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.activeLegPrediction = nil
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                state: state,
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "left \(stop.mbtaStopId)"
            )
            
        case let .transfer(overlapsNext):
            guard !overlapsNext else {
                return [.sendDebugNotification("left \(stop.stopName)")]//
            }
            
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                state: state,
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "left \(stop.stopName)"
            )
        case .intermediate:
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                state: state,
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "left \(stop.stopName)"
            )
        case .final:
            return [
                .endRoute,
                .sendDebugNotification("Journey complete")
            ]
        }
    }
    
    private func prepareTransferPredictionState(state: inout JourneyState, nextStop: ResolvedStop) {
        guard let transferPredictionStop = transferPredictionStop(state: state, transferStop: nextStop) else {
            state.transferLegPrediction = nil
            return
        }

        state.transferLegPrediction = PredictionState(
            predictedStop: transferPredictionStop,
            predictedStopType: .transfer,
            acceptableRouteIds: state.acceptableRouteIds(for: transferPredictionStop),
            loadingState: .loading(stopId: transferPredictionStop.mbtaStopId)
        )
    }
    private func backtrackToStop(state: inout JourneyState) -> [JourneyEffect] {
        let previousMode = state.monitoringMode
        guard let prevStop = state.backtrackToPreviousStop() else {
            return []
        }
        
        // Determine correct mode via look-ahead (same logic as arriveAtStop):
        // if the next stop is underground, stay underground even though
        // the backtracked stop's inherent mode may be surface.
        if let nextStop = state.nextStop, nextStop.monitoringMode == .underground {
            state.monitoringMode = .underground
        } else {
            state.monitoringMode = prevStop.monitoringMode
        }
        
        state.pendingDepartureConfirmation = false
        state.movementStatus = .atStop
        state.activeLegPrediction = PredictionState(
            predictedStop: prevStop,
            predictedStopType: .boarding,
            acceptableRouteIds: state.acceptableRouteIds(for: prevStop),
            loadingState: .loading(stopId: prevStop.mbtaStopId)
        )
        state.transferLegPrediction = nil
        
        var effects: [JourneyEffect] = []
        if state.monitoringMode != previousMode {
            effects.append(.switchMonitoringMode(state.monitoringMode))
        }
        effects.append(.monitorStop(prevStop))
        effects.append(.updateJourneyTiming)
        effects.append(.sendDebugNotification("Backtracked to \(prevStop.stopName)"))
        return effects
    }
    
    private func evaluateTimingRefresh(state: inout JourneyState, isManual: Bool) -> [JourneyEffect] {
        if isManual {
            if state.activeLegPrediction != nil {
                guard let activeStopId = state.activeLegPrediction?.predictedStop.mbtaStopId else { return [] }
                state.activeLegPrediction?.loadingState = .loading(stopId: activeStopId)
            }
            
            if state.transferLegPrediction != nil {
                guard let transferStopId = state.transferLegPrediction?.predictedStop.mbtaStopId else { return []}
                state.transferLegPrediction?.loadingState = .loading(stopId: transferStopId)
            }
        }

        guard state.timingContext != nil else { return [] }
        return [.updateJourneyTiming]
    }

    // MARK: - Journey timing updates

    private func handleJourneyTimingUpdate(state: inout JourneyState, update: JourneyTimingUpdate?) -> [JourneyEffect] {
        guard let update else { return [] }
        
        
        let previousVehicleId = state.trackedVehicleId
        let previousTripId = state.trackedTripId
        //Previous timing state
        let previousTiming = state.timingState.timing
        
        
        state.timingState.refreshSessionId = update.refreshSessionId
        state.timingState.generation = update.generation
        state.timingState.updatedAt = update.fetchedAt
        state.timingState.timing = update.timing

        if var activePrediction = state.activeLegPrediction, let slice = update.predictionSlices.first(where: {
               $0.predictedStopId == activePrediction.predictedStop.id
           }) {
            applyPredictionSlice(slice, to: &activePrediction)
            if activePrediction.predictedStopType == .boarding {
                state.updateVehicleTracking(
                    targetPrediction: activePrediction,
                    predictionResults: slice.livePredictions
                )
            }
            state.activeLegPrediction = activePrediction
        }

        if var transferPrediction = state.transferLegPrediction, let slice = update.predictionSlices.first(where: {
               $0.predictedStopId == transferPrediction.predictedStop.id
           }) {
            applyPredictionSlice(slice, to: &transferPrediction)
            state.transferLegPrediction = transferPrediction
        }
        //Effect assignments
        var effects: [JourneyEffect] = []
        
        //Send the initial recommendation once for a multi-leg journey.
        if state.legOrder.count > 1,
           previousTiming?.recommendedDeparture == nil,
           let recommendation = update.timing.recommendedDeparture,
           let details = BoardingNoticeDetails(
               recommendation: recommendation,
               timingPlan: update.timing,
               legs: state.legOrder
           ) {
            effects.append(.createNotification(intent: .departureRecommendation(details)))
        }

        //A new connection is explained by the progression notification. Only
        //an independently changing assessment reaches this notification path.
        if let previousConnection = previousTiming?.monitoredConnection,
           let currentConnection = update.timing.monitoredConnection,
           previousConnection.isSameConnection(as: currentConnection) {
            let urgencyIncreased = currentConnection.warning.notificationUrgency
                > previousConnection.warning.notificationUrgency
            let becameTightHighConsequence = currentConnection.warning == .tightHighConsequence
                && urgencyIncreased
            let becameNotifiableLikelyMiss = currentConnection.warning == .likelyMiss
                && previousConnection.warning != .likelyMiss
                && (currentConnection.isHighConsequence || previousConnection.isHighConsequence)

            let selectedConnection = update.timing.selectedItinerary?.connections.contains {
                $0.isSameConnection(as: currentConnection)
            } == true
            let updatedEta = update.timing.destinationArrival
            let previousEta = previousTiming?.destinationArrival
            let etaImproved = updatedEta.map { newEta in
                previousEta.map { newEta < $0 } ?? true
            } ?? false
            let recoveredSelectedConnection = previousConnection.warning == .likelyMiss
                && currentConnection.warning.notificationUrgency
                    < previousConnection.warning.notificationUrgency
                && selectedConnection
                && etaImproved

            if becameTightHighConsequence
                || becameNotifiableLikelyMiss
                || recoveredSelectedConnection {
                let departingLeg = state.legOrder.first {
                    $0.id == currentConnection.departingLegId
                }
                let details = ConnectionWarningChangedDetails(
                    departure: update.timing.nextLegDeparture,
                    eta: updatedEta,
                    previousDeparture: previousTiming?.nextLegDeparture,
                    previousEta: previousEta,
                    departingLeg: departingLeg,
                    previousWarning: previousConnection.warning,
                    warning: currentConnection.warning
                )
                effects.append(.createNotification(intent: .connectionWarningChanged(details)))
            }
        }
       
        if state.trackedVehicleId != previousVehicleId || state.trackedTripId != previousTripId {
            effects.append(
                .updateTrackedVehicle(
                    vehicleId: state.trackedVehicleId,
                    tripId: state.trackedTripId
                )
            )
        }
        return effects
    }

    private func applyPredictionSlice(_ slice: PredictionSlice, to predictionState: inout PredictionState) {
        predictionState.cleanArrivedTrains(
            displayPredictions: slice.displayPredictions,
            livePredictions: slice.livePredictions
        )
        let stopId = predictionState.predictedStop.mbtaStopId
        if slice.displayPredictions.isEmpty {
            predictionState.loadingState = .unavailable(
                stopId: stopId,
                message: "No times available"
            )
        } else {
            predictionState.loadingState = .loaded(
                stopId: stopId,
                times: slice.displayPredictions.map(\.display)
            )
        }
    }
    
    private func effectsForNextStop(_ nextStop: ResolvedStop, state: JourneyState, previousMonitoringMode: MonitoringMode, updateTiming: Bool, message: String) -> [JourneyEffect] {
        var effects: [JourneyEffect] = []
        if nextStop.monitoringMode != previousMonitoringMode {
            effects.append(.switchMonitoringMode(nextStop.monitoringMode))
        }
        effects.append(.monitorStop(nextStop))
        if updateTiming {
            effects.append(.updateJourneyTiming)
        }

        if let timingPlan = state.timingState.timing,
           let resolvedLeg = state.currentLeg,
           let legTiming = timingPlan.currentLeg?.resolvedLegId == resolvedLeg.id
                ? timingPlan.currentLeg
                : timingPlan.selectedItinerary?.legs.first(where: { $0.resolvedLegId == resolvedLeg.id }) {
            if nextStop.journeyRole == .final,
               let details = UpcomingArrivalNoticeDetails(
                   legTiming: legTiming,
                   connectionTiming: nil,
                   legs: state.legOrder
               ) {
                effects.append(.createNotification(intent: .destinationNext(details)))
            } else if case .transfer = nextStop.journeyRole,
                      let connection = timingPlan.monitoredConnection,
                      connection.arrivingLegId == legTiming.resolvedLegId,
                      let details = UpcomingArrivalNoticeDetails(
                          legTiming: legTiming,
                          connectionTiming: connection,
                          legs: state.legOrder
                      ) {
                effects.append(.createNotification(intent: .transferApproaching(details)))
            }
        }

        effects.append(.sendDebugNotification(message))
        return effects
    }

    private func transferPredictionStop(state: JourneyState, transferStop: ResolvedStop) -> ResolvedStop? {
        guard case .transfer = transferStop.journeyRole,
              let nextStop = state.nextStop,
              case .boarding = nextStop.journeyRole else { return nil }
        return nextStop
    }
}

//Some Journey Effects need to happen in strict order of operations to work effectively
enum JourneyEffect: Equatable {
    case switchMonitoringMode(MonitoringMode) //1
    case monitorStop(ResolvedStop) //2
    case updateJourneyTiming
    
    case sendDebugNotification(String)
    case createNotification(intent:JourneyNotificationIntent)
    case scheduleEndRoute(seconds: Int)
    case endRoute
    
    case updateTrackedVehicle(vehicleId: String?, tripId: String?)
    case resetTrackingState
    case refreshTripPath(tripId: String)
    case searchForVehicle
}

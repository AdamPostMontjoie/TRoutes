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
    
    func reduce(
        state: inout JourneyState,
        timingUpdate: JourneyTimingUpdate? = nil,
        isManual: Bool = false
    ) -> [JourneyEffect] {
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
            var effects: [JourneyEffect] = [.updateJourneyTiming]
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            if let nextStop = state.nextStop {
                if state.monitoringMode == .surface && nextStop.monitoringMode == .underground {
                    state.monitoringMode = .underground
                    effects.append(.switchMonitoringMode(.underground))
                }
                effects.append(.monitorStop(stop))
            }
            effects.append(.sendNotification("entered \(stop.stopName)"))
            return effects
            
        case let .transfer(overlapsNext):
            guard overlapsNext else {
                state.activeLegPrediction = nil
                state.transferLegPrediction = nil
                return [
                    .updateJourneyTiming,
                    .sendNotification("entered \(stop.stopName)")
                ]
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
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "transfered to \(nextStop.stopName)",
                userMessage: "Transfer here!"
            )
            
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
            if state.timingContext != nil {
                effects.append(.updateJourneyTiming)
            }
            effects.append(.sendNotification("entered \(stop.stopName)"))
            return effects
            
        case .final:
            return [
                .scheduleEndRoute(seconds: 60),
                .sendNotification("entered \(stop.stopName)", user: "You have arrived at your destination")
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
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "left \(stop.mbtaStopId)"
            )
            
        case let .transfer(overlapsNext):
            guard !overlapsNext else {
                return [.sendNotification("left \(stop.stopName)")]
            }
            
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
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
                previousMonitoringMode: previousMonitoringMode,
                updateTiming: state.timingContext != nil,
                message: "left \(stop.stopName)"
            )
        case .final:
            return [
                .endRoute,
                .sendNotification("Journey complete!")
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
        effects.append(.sendNotification("Backtracked to \(prevStop.stopName)"))
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

    private func handleJourneyTimingUpdate(
        state: inout JourneyState,
        update: JourneyTimingUpdate?
    ) -> [JourneyEffect] {
        guard let update else { return [] }

        state.timingState.status = update.status
        state.timingState.refreshSessionId = update.refreshSessionId
        state.timingState.generation = update.generation
        state.timingState.updatedAt = update.fetchedAt
        state.timingState.recommendedDeparture = update.recommendedDeparture
        state.timingState.currentLegArrival = update.currentLegArrival
        state.timingState.destinationArrival = update.destinationArrival
        state.timingState.connection = update.connection

        let previousVehicleId = state.trackedVehicleId
        let previousTripId = state.trackedTripId

        if var activePrediction = state.activeLegPrediction,
           let slice = update.predictionSlices.first(where: {
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

        if var transferPrediction = state.transferLegPrediction,
           let slice = update.predictionSlices.first(where: {
               $0.predictedStopId == transferPrediction.predictedStop.id
           }) {
            applyPredictionSlice(slice, to: &transferPrediction)
            state.transferLegPrediction = transferPrediction
        }

        var effects: [JourneyEffect] = []
        if state.trackedVehicleId != previousVehicleId
            || state.trackedTripId != previousTripId {
            effects.append(
                .updateTrackedVehicle(
                    vehicleId: state.trackedVehicleId,
                    tripId: state.trackedTripId
                )
            )
        }
        return effects
    }

    private func applyPredictionSlice(
        _ slice: PredictionSlice,
        to predictionState: inout PredictionState
    ) {
        predictionState.cleanArrivedTrains(
            displayPredictions: slice.predictions,
            livePredictions: slice.livePredictions
        )
        let stopId = predictionState.predictedStop.mbtaStopId
        if slice.predictions.isEmpty {
            predictionState.loadingState = .unavailable(
                stopId: stopId,
                message: "No times available"
            )
        } else {
            predictionState.loadingState = .loaded(
                stopId: stopId,
                times: slice.predictions.map(\.display)
            )
        }
    }
    
    private func effectsForNextStop(
        _ nextStop: ResolvedStop,
        previousMonitoringMode: MonitoringMode,
        updateTiming: Bool,
        message: String,
        userMessage: String? = nil
    ) -> [JourneyEffect] {
        var effects: [JourneyEffect] = []
        if nextStop.monitoringMode != previousMonitoringMode {
            effects.append(.switchMonitoringMode(nextStop.monitoringMode))
        }
        effects.append(.monitorStop(nextStop))
        if updateTiming {
            effects.append(.updateJourneyTiming)
        }
        var nextStopUserMessage = userMessage
        if userMessage == nil {
            if nextStop.journeyRole == .final {
                nextStopUserMessage = "Your destination \(nextStop.stopName) is the next stop!"
            } else if case .transfer = nextStop.journeyRole {
                nextStopUserMessage = "Get ready to transfer! \(nextStop.stopName) is next."
            }
        }
    
        effects.append(.sendNotification(message, user: nextStopUserMessage))
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
    
    case sendNotification(_ debug: String, user: String? = nil)
    case scheduleEndRoute(seconds: Int)
    case endRoute
    
    case updateTrackedVehicle(vehicleId: String?, tripId: String?)
    case resetTrackingState
    case refreshTripPath(tripId: String)
    case searchForVehicle
}

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
    case handleNewPredictions
    case evaluatePredictionRefresh
    
    func reduce(state: inout JourneyState, predictions: [TransitPrediction]? = nil) -> [JourneyEffect] {
        switch self {
        case .arriveAtStop:
            return arriveAtStop(state: &state)
        case .departFromStop:
            return departFromStop(state: &state)
        case .backtrackToStop:
            return backtrackToStop(state: &state)
        case .handleNewPredictions:
            return handleNewPredictions(state: &state, predictions:predictions ?? nil)
        case .evaluatePredictionRefresh:
            return evaluatePredictionRefresh(state: &state)
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
            var effects: [JourneyEffect] = [.fetchPredictions]
            
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
                return [.sendNotification("entered \(stop.stopName)")]
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
                fetchPredictions: true,
                message: "transfered to \(nextStop.mbtaStopId)",
                userMessage: "Transfer here for the \(nextStop.mbtaRouteId)"
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
            effects.append(.sendNotification("entered \(stop.stopName)"))
            return effects
            
        case .final:
            return [.sendNotification("entered \(stop.mbtaStopId)", user: "You have arrived at your destination")]
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
                fetchPredictions: state.activeLegPrediction != nil || state.transferLegPrediction != nil,
                message: "left \(stop.mbtaStopId)"
            )
            
        case let .transfer(overlapsNext):
            guard !overlapsNext else {
                return [.sendNotification("left \(stop.mbtaStopId)")]
            }
            
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: state.activeLegPrediction != nil || state.transferLegPrediction != nil,
                message: "left \(stop.mbtaStopId)"
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
                fetchPredictions: state.activeLegPrediction != nil || state.transferLegPrediction != nil,
                message: "left \(stop.mbtaStopId)"
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
        effects.append(.fetchPredictions)
        effects.append(.sendNotification("Backtracked to \(prevStop.stopName)"))
        return effects
    }
    
    private func evaluatePredictionRefresh(state: inout JourneyState) -> [JourneyEffect] {
        guard state.activeLegPrediction != nil || state.transferLegPrediction != nil else { return [] }
        
        if state.activeLegPrediction != nil {
            state.activeLegPrediction?.loadingState = .loading(stopId: state.activeLegPrediction!.predictedStop.mbtaStopId)
        }
        if state.transferLegPrediction != nil {
            state.transferLegPrediction?.loadingState = .loading(stopId: state.transferLegPrediction!.predictedStop.mbtaStopId)
        }
        
        return [.fetchPredictions]
    }
    
    private func handleNewPredictions(state: inout JourneyState, predictions: [TransitPrediction]?) -> [JourneyEffect] {
        guard let predictions else { return [] }
        let times = predictions.map(\.display)
        
        let lastTrackedVehicle = state.trackedVehicleId
        
        let isTransfer = state.activeLegPrediction == nil && state.transferLegPrediction != nil
        guard var targetPrediction = isTransfer ? state.transferLegPrediction : state.activeLegPrediction else { return [] }
        
        if times.isEmpty {
            targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "No times available")
        } else {
            targetPrediction.loadingState = .loaded(stopId: targetPrediction.predictedStop.mbtaStopId, times: times)
            targetPrediction.cleanArrivedTrains(newPredictions: predictions)
            
            if !isTransfer, targetPrediction.predictedStopType == .boarding {
                state.updateVehicleTracking(targetPrediction: targetPrediction, predictionResults: predictions)
            }
        }
        // Save prediction state
        if isTransfer {
            state.transferLegPrediction = targetPrediction
        } else {
            state.activeLegPrediction = targetPrediction
        }
        var effects: [JourneyEffect] = []
        if state.trackedVehicleId != lastTrackedVehicle {
            effects.append(.updateTrackedVehicle(vehicleId: state.trackedVehicleId, tripId: state.trackedTripId))
        }
        return effects
    }
    
    private func effectsForNextStop(
        _ nextStop: ResolvedStop,
        previousMonitoringMode: MonitoringMode,
        fetchPredictions: Bool,
        message: String,
        userMessage: String? = nil
    ) -> [JourneyEffect] {
        var effects: [JourneyEffect] = []
        if nextStop.monitoringMode != previousMonitoringMode {
            effects.append(.switchMonitoringMode(nextStop.monitoringMode))
        }
        effects.append(.monitorStop(nextStop))
        if fetchPredictions {
            effects.append(.fetchPredictions)
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

//Journey Effects need to happen in strict order of operations to work effectively
enum JourneyEffect: Equatable {
    case switchMonitoringMode(MonitoringMode) //first in order
    case monitorStop(ResolvedStop) //second
    case fetchPredictions//third
    
    case sendNotification(_ debug: String, user: String? = nil)
    case endRoute
    
    case updateTrackedVehicle(vehicleId: String?, tripId: String?)
    case resetTrackingState
    case refreshTripPath(tripId: String)
}

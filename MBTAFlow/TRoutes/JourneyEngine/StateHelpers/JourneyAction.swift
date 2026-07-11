//
//  JourneyAction.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/19/26.
//

///Determines what we need to do after receiving a JourneyCommand based on JourneyState
enum JourneyAction: Equatable {
    case arriveAtStop
    case departFromStop
    case backtrackToStop
    case evaluatePredictionRefresh
    
    func reduce(state: inout JourneyState) -> [JourneyEffect] {
        switch self {
        case .arriveAtStop:
            return arriveAtStop(state: &state)
        case .departFromStop:
            return departFromStop(state: &state)
        case .backtrackToStop:
            return backtrackToStop(state: &state)
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
            state.predictionState = PredictionState(
                predictedStop: stop,
                predictedStopType: .boarding,
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
            effects.append(.sendNotification("entered \(stop.mbtaStopId)"))
            return effects
            
        case let .transfer(overlapsNext):
            guard overlapsNext else {
                state.predictionState = nil
                return [.sendNotification("entered \(stop.mbtaStopId)")]
            }
            
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.movementStatus = .atStop
            state.predictionState = PredictionState(
                predictedStop: nextStop,
                predictedStopType: .boarding,
                loadingState: .loading(stopId: nextStop.mbtaStopId)
            )
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: true,
                message: "transfered to \(nextStop.mbtaStopId)",
                userMessage: "Transfer here for the \(nextStop.mbtaRouteId)"
            )
            
        case .intermediate:
            state.predictionState = nil
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            var effects: [JourneyEffect] = []
            if let nextStop = state.nextStop {
                if state.monitoringMode == .surface && nextStop.monitoringMode == .underground {
                    state.monitoringMode = .underground
                    effects.append(.switchMonitoringMode(.underground))
                }
                effects.append(.monitorStop(stop))
            }
            effects.append(.sendNotification("entered \(stop.mbtaStopId)"))
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
            
            prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: state.predictionState != nil,
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
                fetchPredictions: state.predictionState != nil,
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
                fetchPredictions: state.predictionState != nil,
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
            state.predictionState = nil
            return
        }

        state.predictionState = PredictionState(
            predictedStop: transferPredictionStop,
            predictedStopType: .transfer,
            loadingState: .loading(stopId: transferPredictionStop.mbtaStopId)
        )
    }
    private func backtrackToStop(state: inout JourneyState) -> [JourneyEffect] {
        guard let prevStop = state.backtrackToPreviousStop() else {
            return []
        }
        
        state.pendingDepartureConfirmation = false
        state.movementStatus = .atStop
        state.predictionState = PredictionState(
            predictedStop: prevStop,
            predictedStopType: .boarding,
            loadingState: .loading(stopId: prevStop.mbtaStopId)
        )
        
        // Return effects to switch mode if needed and re-monitor the stop
        var effects: [JourneyEffect] = []
        effects.append(.monitorStop(prevStop))
        effects.append(.fetchPredictions)
        effects.append(.sendNotification("Backtracked to \(prevStop.stopName)"))
        return effects
    }
    
    private func evaluatePredictionRefresh(state: inout JourneyState) -> [JourneyEffect] {
        guard state.predictionState != nil else { return [] }
        return [.fetchPredictions]
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
        effects.append(.sendNotification(message, user: userMessage))
        return effects
    }

    private func transferPredictionStop(state: JourneyState, transferStop: ResolvedStop) -> ResolvedStop? {
        guard case .transfer = transferStop.journeyRole,
              let nextStop = state.nextStop,
              case .boarding = nextStop.journeyRole else { return nil }
        return nextStop
    }
}

enum JourneyEffect: Equatable {
    case monitorStop(ResolvedStop) // rename start monitoring for?
    case fetchPredictions
    case switchMonitoringMode(MonitoringMode)
    case sendNotification(_ debug: String, user: String? = nil)
    case endRoute
    
    case updateTrackedVehicle(vehicleId: String?, tripId: String?)
    case resetTrackingState
    case refreshTripPath(tripId: String)
}

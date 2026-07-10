//
//  JourneyAction.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/19/26.
//

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
            state.predictionState = .loading(stopId: stop.mbtaStopId)
            var effects: [JourneyEffect] = [.fetchPredictions(stop)]
            
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
                state.predictionState = .notNeeded
                return [.sendNotification("entered \(stop.mbtaStopId)")]
            }
            
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.movementStatus = .atStop
            state.predictionState = .loading(stopId: nextStop.mbtaStopId)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: true,
                message: "transfered to \(nextStop.mbtaStopId)",
                userMessage: "Transfer here for the \(nextStop.mbtaRouteId)"
            )
            
        case .intermediate:
            state.predictionState = .notNeeded
            
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
            
            state.predictionState = .notNeeded
            let transferPredictionStop = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                transferPredictionStop: transferPredictionStop,
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
            
            state.predictionState = .notNeeded
            let transferPredictionStop = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                transferPredictionStop: transferPredictionStop,
                message: "left \(stop.mbtaStopId)"
            )
        case .intermediate:
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.predictionState = .notNeeded
            let transferPredictionStop = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                transferPredictionStop: transferPredictionStop,
                message: "left \(stop.mbtaStopId)"
            )
        case .final:
            return [
                .endRoute,
                .sendNotification("Journey complete!")
            ]
        }
    }
    
    private func prepareTransferPredictionState(state: inout JourneyState, nextStop: ResolvedStop) -> ResolvedStop? {
        guard let transferPredictionStop = transferPredictionStop(state: state, transferStop: nextStop) else {
            state.transferPredictionState = .notNeeded
            return nil
        }

        state.transferPredictionState = .loading(stopId: transferPredictionStop.mbtaStopId)
        return transferPredictionStop
    }
    private func backtrackToStop(state: inout JourneyState) -> [JourneyEffect] {
        guard let prevStop = state.backtrackToPreviousStop() else {
            return []
        }
        
        state.pendingDepartureConfirmation = false
        state.movementStatus = .atStop
        state.predictionState = .loading(stopId: prevStop.mbtaStopId)
        
        // Return effects to switch mode if needed and re-monitor the stop
        var effects: [JourneyEffect] = []
        effects.append(.monitorStop(prevStop))
        effects.append(.fetchPredictions(prevStop))
        effects.append(.sendNotification("Backtracked to \(prevStop.stopName)"))
        return effects
    }
    
    private func evaluatePredictionRefresh(state: inout JourneyState) -> [JourneyEffect] {
        guard let currentStop = state.currentStop else { return [] }
        
        var effects: [JourneyEffect] = []
        switch state.predictionState {
        case .loaded, .unavailable, .loading:
            effects.append(.fetchPredictions(currentStop))
        case .notNeeded:
            break
        }
        
        if state.movementStatus == .enRoute {
            switch state.transferPredictionState {
            case .loaded, .unavailable, .loading:
                if let currentLeg = state.currentLeg, let legFinalStop = currentLeg.stops.last {
                    let legTotalStops = currentLeg.stops.count
                    let legCurrentIndex = currentStop.legStopIndex
                    let stopsRemainingInLeg = legTotalStops - legCurrentIndex
                    let isTransferLeg = state.legIndex < state.legOrder.count - 1
                    
                    if isTransferLeg && stopsRemainingInLeg == 1 {
                        let transferPredictionStop = transferPredictionStop(state: state, transferStop: legFinalStop)
                        if let transferPredictionStop {
                            effects.append(.fetchTransferPredictions(transferPredictionStop))
                        }
                    }
                }
            case .notNeeded:
                break
            }
        }
        return effects
    }
    private func effectsForNextStop(
        _ nextStop: ResolvedStop,
        previousMonitoringMode: MonitoringMode,
        fetchPredictions: Bool,
        transferPredictionStop: ResolvedStop? = nil,
        message: String,
        userMessage: String? = nil
    ) -> [JourneyEffect] {
        var effects: [JourneyEffect] = []
        if nextStop.monitoringMode != previousMonitoringMode {
            effects.append(.switchMonitoringMode(nextStop.monitoringMode))
        }
        effects.append(.monitorStop(nextStop))
        if fetchPredictions {
            effects.append(.fetchPredictions(nextStop))
        }
        if let transferPredictionStop {
            effects.append(.fetchTransferPredictions(transferPredictionStop))
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
    case fetchPredictions(ResolvedStop)
    case fetchTransferPredictions(ResolvedStop)
    case switchMonitoringMode(MonitoringMode)
    case sendNotification(_ debug: String, user: String? = nil)
    case endRoute
    
    case updateTrackedVehicle(vehicleId: String?, tripId: String?)
    case resetTrackingState
    case refreshTripTrackingData(tripId: String)
}

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
        
        state.movementStatus = .atStop
        
        switch stop.journeyRole {
        case .boarding:
            state.predictionState = .loading(stopId: stop.mbtaStopId)
            var effects: [JourneyEffect] = [.fetchPredictions(stop)]
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            let nextIndex = state.stopIndex + 1
            if state.stopOrder.indices.contains(nextIndex) {
                let nextStop = state.stopOrder[nextIndex]
                if nextStop.monitoringMode != state.monitoringMode {
                    state.monitoringMode = nextStop.monitoringMode
                    effects.append(.switchMonitoringMode(nextStop.monitoringMode))
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
                message: "transfered to \(nextStop.mbtaStopId)"
            )
        case .intermediate:
            state.predictionState = .notNeeded
            
            // Look ahead to see if the next stop requires a different monitoring mode,
            let nextIndex = state.stopIndex + 1
            var effects: [JourneyEffect] = []
            if state.stopOrder.indices.contains(nextIndex) {
                let nextStop = state.stopOrder[nextIndex]
                if nextStop.monitoringMode != state.monitoringMode {
                    state.monitoringMode = nextStop.monitoringMode
                    effects.append(.switchMonitoringMode(nextStop.monitoringMode))
                }
                effects.append(.monitorStop(stop))
            }
            effects.append(.sendNotification("entered \(stop.mbtaStopId)"))
            return effects
            
        case .final:
            return [.sendNotification("entered \(stop.mbtaStopId)")]
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
            let fetchTransfer = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                fetchTransferPredictions: fetchTransfer,
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
            let fetchTransfer = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                fetchTransferPredictions: fetchTransfer,
                message: "left \(stop.mbtaStopId)"
            )
        case .intermediate:
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.predictionState = .notNeeded
            let fetchTransfer = prepareTransferPredictionState(state: &state, nextStop: nextStop)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                fetchTransferPredictions: fetchTransfer,
                message: "left \(stop.mbtaStopId)"
            )
        case .final:
            return [
                .endRoute,
                .sendNotification("Journey complete!")
            ]
        }
    }
    
    private func prepareTransferPredictionState(state: inout JourneyState, nextStop: ResolvedStop) -> Bool {
        if case .transfer = nextStop.journeyRole {
            state.transferPredictionState = .loading(stopId: nextStop.mbtaStopId)
            return true
        } else {
            state.transferPredictionState = .notNeeded
            return false
        }
    }
    private func backtrackToStop(state: inout JourneyState) -> [JourneyEffect] {
        guard let prevStop = state.backtrackToPreviousStop() else {
            return []
        }
        
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
        
        if state.movementStatus == .atStop {
            switch state.predictionState {
            case .loaded, .unavailable, .loading:
                // We fetch if it's loaded, unavailable, or even loading (if it got stuck)
                // but let's stick to the previous timer logic.
                return [.fetchPredictions(currentStop)]
            case .notNeeded:
                return []
            }
        } else if state.movementStatus == .enRoute {
            switch state.transferPredictionState {
            case .loaded, .unavailable, .loading:
                if let currentLeg = state.currentLeg, let legFinalStop = currentLeg.stops.last {
                    let legTotalStops = currentLeg.stops.count
                    let legCurrentIndex = currentStop.legStopIndex
                    let stopsRemainingInLeg = legTotalStops - legCurrentIndex
                    let isTransferLeg = state.legIndex < state.legOrder.count - 1
                    
                    if isTransferLeg && stopsRemainingInLeg == 1 {
                        return [.fetchTransferPredictions(legFinalStop)]
                    }
                }
            case .notNeeded:
                break
            }
        }
        return []
    }
    private func effectsForNextStop(
        _ nextStop: ResolvedStop,
        previousMonitoringMode: MonitoringMode,
        fetchPredictions: Bool,
        fetchTransferPredictions: Bool = false,
        message: String
    ) -> [JourneyEffect] {
        var effects: [JourneyEffect] = []
        if nextStop.monitoringMode != previousMonitoringMode {
            effects.append(.switchMonitoringMode(nextStop.monitoringMode))
        }
        effects.append(.monitorStop(nextStop))
        if fetchPredictions {
            effects.append(.fetchPredictions(nextStop))
        }
        if fetchTransferPredictions {
            effects.append(.fetchTransferPredictions(nextStop))
        }
        effects.append(.sendNotification(message))
        return effects
    }
}

enum JourneyEffect: Equatable {
    case monitorStop(ResolvedStop) // rename start monitoring for?
    case fetchPredictions(ResolvedStop)
    case fetchTransferPredictions(ResolvedStop)
    case switchMonitoringMode(MonitoringMode)
    case sendNotification(String)
    case endRoute
}

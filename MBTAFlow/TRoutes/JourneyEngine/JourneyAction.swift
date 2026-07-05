//
//  JourneyAction.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/19/26.
//

enum JourneyAction: Equatable {
    case arriveAtStop
    case departFromStop

    func reduce(state: inout JourneyState) -> [JourneyEffect] {
        switch self {
        case .arriveAtStop:
            return arriveAtStop(state: &state)
        case .departFromStop:
            return departFromStop(state: &state)
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
            return [
                .fetchPredictions(stop),
                .sendNotification("entered \(stop.mbtaStopId)")
            ]
        
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
            return [.sendNotification("entered \(stop.mbtaStopId)")]
        
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
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
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
            
            state.predictionState = .loading(stopId: nextStop.mbtaStopId)
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: true,
                message: "left \(stop.mbtaStopId)"
            )
        //handle this
        case .intermediate:
            let previousMonitoringMode = state.monitoringMode
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }

            state.predictionState = .notNeeded
            return effectsForNextStop(
                nextStop,
                previousMonitoringMode: previousMonitoringMode,
                fetchPredictions: false,
                message: "left \(stop.mbtaStopId)"
            )
        case .final:
            return [
                .endRoute,
                .sendNotification("Journey complete!")
            ]
        }
    }
    private func effectsForNextStop(
        _ nextStop: ResolvedStop,
        previousMonitoringMode: MonitoringMode,
        fetchPredictions: Bool,
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
        effects.append(.sendNotification(message))
        return effects
    }
}

enum JourneyEffect: Equatable {
    case monitorStop(ResolvedStop) // rename start monitoring for?
    case fetchPredictions(ResolvedStop)
    case switchMonitoringMode(MonitoringMode)
    case sendNotification(String)
    case endRoute
}

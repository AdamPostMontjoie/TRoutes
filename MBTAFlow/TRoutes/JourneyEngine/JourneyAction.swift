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
            state.needTimes = true
            state.activePredictionTimes = []
            return [
                .fetchPredictions(stop),
                .sendNotification("entered \(stop.mbtaStopId)")
            ]
        
        case let .transfer(overlapsNext):
            guard overlapsNext else {
                state.activePredictionTimes = []
                state.needTimes = false
                return [.sendNotification("entered \(stop.mbtaStopId)")]
            }
            
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.movementStatus = .atStop
            state.needTimes = true
            state.activePredictionTimes = []
            return [
                .registerRegion(nextStop),
                .fetchPredictions(nextStop),
                .sendNotification("transfered to \(nextStop.mbtaStopId)")
            ]
        
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
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.activePredictionTimes = []
            state.needTimes = false
            return [
                .registerRegion(nextStop),
                .sendNotification("left \(stop.mbtaStopId)")
            ]
        
        case let .transfer(overlapsNext):
            guard !overlapsNext else {
                return [.sendNotification("left \(stop.mbtaStopId)")]
            }
            
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.activePredictionTimes = []
            state.needTimes = true
            return [
                .registerRegion(nextStop),
                .fetchPredictions(nextStop),
                .sendNotification("left \(stop.mbtaStopId)")
            ]
        
        case .final:
            return [
                .endRoute,
                .sendNotification("Journey complete!")
            ]
        }
    }
}

enum JourneyEffect: Equatable {
    case registerRegion(Stop)
    case fetchPredictions(Stop)
    case sendNotification(String)
    case endRoute
}

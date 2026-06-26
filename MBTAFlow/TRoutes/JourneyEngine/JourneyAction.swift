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
            
            guard let nextStop = state.advanceToNextStop() else {
                return []
            }
            
            state.movementStatus = .atStop
            state.predictionState = .loading(stopId: nextStop.mbtaStopId)
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
            
            state.predictionState = .notNeeded
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
            
            state.predictionState = .loading(stopId: nextStop.mbtaStopId)
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

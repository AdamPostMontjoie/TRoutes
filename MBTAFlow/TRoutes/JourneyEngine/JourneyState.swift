//
//  JourneyState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct JourneyState: Equatable, Codable {
    let route: UserRoute
    let stopSequence: [Stop]
    
    var stopIndex: Int = 0
    var movementStatus: MovementStatus = .enRoute
    var predictionState: PredictionState = .notNeeded
    var monitoringMode:MonitoringMode = .underground
    
    var currentStop: Stop? {
        guard stopSequence.indices.contains(stopIndex) else {
            return nil
        }
        return stopSequence[stopIndex]
    }
    
    var isEndOfJourney: Bool {
        return stopIndex == stopSequence.count - 1 && movementStatus == .atStop
    }
    
    init(route: UserRoute) {
        self.route = route
        var sequence: [Stop] = []
        
        for index in route.legs.indices {
            let isLastLeg = index == route.legs.indices.last
            var startStop = route.legs[index].startStop
            var endStop = route.legs[index].endStop
            
            startStop.journeyRole = .boarding
            
            if isLastLeg {
                endStop.journeyRole = .final
            } else {
                let nextStartStop = route.legs[index + 1].startStop
                endStop.journeyRole = .transfer(
                    overlapsNext: endStop.mbtaStopId == nextStartStop.mbtaStopId
                )
            }
            
            sequence.append(startStop)
            sequence.append(endStop)
        }
        
        self.stopSequence = sequence
        self.predictionState = sequence.first.map { .loading(stopId: $0.mbtaStopId) } ?? .notNeeded
    }
    
    mutating func advanceToNextStop() -> Stop? {
        let nextIndex = stopIndex + 1
        guard stopSequence.indices.contains(nextIndex) else {
            return nil
        }

        stopIndex = nextIndex
        return stopSequence[stopIndex]
    }

}

enum PredictionState: Equatable, Codable {
    case notNeeded
    case loading(stopId: String)
    case loaded(stopId: String, times: [String])
    case unavailable(stopId: String, message: String)
}

enum MovementStatus: Codable {
    case enRoute
    case atStop
}

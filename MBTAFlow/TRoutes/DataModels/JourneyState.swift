//
//  JourneyState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct JourneyState: Equatable, Codable {
    let route: RouteStruct
    let stopSequence: [Stop]
    
    var stopIndex: Int = 0
    var movementStatus: MovementStatus = .enRoute
    var activePredictionTimes: [String] = []
    var warningMessage: String?
    var needTimes: Bool = true
    
    var currentStop: Stop? {
        guard stopSequence.indices.contains(stopIndex) else {
            return nil
        }
        return stopSequence[stopIndex]
    }
    
    var isEndOfJourney: Bool {
        return stopIndex == stopSequence.count - 1 && movementStatus == .atStop
    }
    
    init(route: RouteStruct) {
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

enum MovementStatus: Codable {
    case enRoute
    case atStop
}

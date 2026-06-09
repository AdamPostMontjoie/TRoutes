//
//  JourneyState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct JourneyState: Equatable {
    let route: RouteStruct
    let stopSequence: [Stop]
    
    var stopIndex: Int = 0
    var movementStatus: MovementStatus = .enRoute
    var activePredictionTimes: [String] = []
    
    var currentStop: Stop {
        return stopSequence[stopIndex]
    }
    
    var isEndOfJourney: Bool {
        return stopIndex == stopSequence.count - 1 && movementStatus == .atStop
    }
    
    init(route: RouteStruct) {
        self.route = route
        self.stopSequence = route.legs.flatMap { [$0.startStop, $0.endStop] }
    }
}

struct StopState:Equatable {
    var stop:Stop
    init(stop: Stop) {
        self.stop = stop
    }
}

enum MovementStatus {
    case enRoute
    case atStop
}

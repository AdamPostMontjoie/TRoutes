//
//  JourneyState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct JourneyState: Equatable, Codable {
    let route: ResolvedUserRoute
    let stopOrder: [ResolvedStop]
    let legOrder:[ResolvedLeg]
    
    var stopIndex: Int = 0
    var legIndex:Int = 0
    var movementStatus: MovementStatus = .enRoute
    var predictionState: PredictionState = .notNeeded
    var monitoringMode:MonitoringMode = .underground
    
    var currentLeg:ResolvedLeg? {
        guard legOrder.indices.contains(legIndex) else {
            return nil
        }
        return legOrder[legIndex]
    }
    var currentStop: ResolvedStop? {
        guard stopOrder.indices.contains(stopIndex) else {
            return nil
        }
        return stopOrder[stopIndex]
    }
    
    var isEndOfJourney: Bool {
        return stopIndex == stopOrder.count - 1 && movementStatus == .atStop
    }
    
    init(route: ResolvedUserRoute) {
        self.route = route
        let stops = route.legs.flatMap(\.stops)
        self.stopOrder = stops
        self.legOrder = route.legs
        self.monitoringMode = stops.first?.monitoringMode ?? .underground
        self.predictionState = stops.first.map { .loading(stopId: $0.mbtaStopId) } ?? .notNeeded
    }
    
    //determine monitoring mode here? or in journey actions?
    mutating func advanceToNextStop() -> ResolvedStop? {
        let nextIndex = stopIndex + 1
        guard stopOrder.indices.contains(nextIndex) else {
            return nil
        }

        let nextStop = stopOrder[nextIndex]
        stopIndex = nextIndex
        monitoringMode = nextStop.monitoringMode

        if legOrder.indices.contains(nextStop.legIndex) {
            legIndex = nextStop.legIndex
        }

        return nextStop
    }
    //go back to prev stop
    mutating func backtrackToPreviousStop() -> ResolvedStop? {
        let prevIndex = stopIndex - 1
        guard stopOrder.indices.contains(prevIndex) else { return nil }
        stopIndex = prevIndex
        let prevStop = stopOrder[prevIndex]
        monitoringMode = prevStop.monitoringMode
        if legOrder.indices.contains(prevStop.legIndex) {
            legIndex = prevStop.legIndex
        }
        return prevStop
    }
    
    //
    mutating func advanceToNextLeg() -> ResolvedLeg? {
        let nextIndex = legIndex + 1
        guard legOrder.indices.contains(nextIndex) else {
            return nil
        }
        
        legIndex = nextIndex
        return legOrder[legIndex]
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

enum MonitoringMode:Equatable, Codable {
    case underground
    case surface
}

import Foundation

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
    var activeLegPrediction: PredictionState? = nil
    var transferLegPrediction: PredictionState? = nil
    var monitoringMode:MonitoringMode = .underground
    var pendingDepartureConfirmation: Bool = false
    
    // Persisted vehicle tracking properties
    var trackedVehicleId: String? = nil
    var trackedTripId: String? = nil
    var trackedBoardingStopId: String? = nil
    
    var timeSaved: Date = Date()
    
    var currentLeg:ResolvedLeg? {
        guard legOrder.indices.contains(legIndex) else {
            return nil
        }
        return legOrder[legIndex]
    }

    func acceptableRouteIds(for stop: ResolvedStop) -> [String] {
        guard legOrder.indices.contains(stop.legIndex) else {
            return []
        }
        return legOrder[stop.legIndex].acceptableRouteIds
    }
    var currentStop: ResolvedStop? {
        guard stopOrder.indices.contains(stopIndex) else {
            return nil
        }
        return stopOrder[stopIndex]
    }
    
    var previousStop: ResolvedStop? {
        let previousIndex = stopIndex - 1
        guard stopOrder.indices.contains(previousIndex) else {
            return nil
        }
        return stopOrder[previousIndex]
    }
    
    var nextStop: ResolvedStop? {
        let nextIndex = stopIndex + 1
        guard stopOrder.indices.contains(nextIndex) else {
            return nil
        }
        return stopOrder[nextIndex]
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
        if let firstStop = stops.first, let firstLeg = route.legs.first {
            self.activeLegPrediction = PredictionState(
                predictedStop: firstStop,
                predictedStopType: .boarding,
                acceptableRouteIds: firstLeg.acceptableRouteIds,
                loadingState: .loading(stopId: firstStop.mbtaStopId)
            )
        } else {
            self.activeLegPrediction = nil
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case route
        case stopOrder
        case legOrder
        case stopIndex
        case legIndex
        case movementStatus
        case activeLegPrediction
        case transferLegPrediction
        case monitoringMode
        case pendingDepartureConfirmation
        case trackedVehicleId
        case trackedTripId
        case trackedBoardingStopId
        case timeSaved
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        route = try container.decode(ResolvedUserRoute.self, forKey: .route)
        stopOrder = try container.decode([ResolvedStop].self, forKey: .stopOrder)
        legOrder = try container.decode([ResolvedLeg].self, forKey: .legOrder)
        stopIndex = try container.decode(Int.self, forKey: .stopIndex)
        legIndex = try container.decode(Int.self, forKey: .legIndex)
        movementStatus = try container.decode(MovementStatus.self, forKey: .movementStatus)
        activeLegPrediction = try container.decodeIfPresent(PredictionState.self, forKey: .activeLegPrediction)
        transferLegPrediction = try container.decodeIfPresent(PredictionState.self, forKey: .transferLegPrediction)
        monitoringMode = try container.decode(MonitoringMode.self, forKey: .monitoringMode)
        pendingDepartureConfirmation = try container.decodeIfPresent(Bool.self, forKey: .pendingDepartureConfirmation) ?? false
        trackedVehicleId = try container.decodeIfPresent(String.self, forKey: .trackedVehicleId)
        trackedTripId = try container.decodeIfPresent(String.self, forKey: .trackedTripId)
        trackedBoardingStopId = try container.decodeIfPresent(String.self, forKey: .trackedBoardingStopId)
        timeSaved = try container.decodeIfPresent(Date.self, forKey: .timeSaved) ?? Date()
    }
    
    //determine monitoring mode here? or in journey actions?
    mutating func advanceToNextStop() -> ResolvedStop? {
        guard let nextStop else {
            return nil
        }

        stopIndex += 1
        monitoringMode = nextStop.monitoringMode

        if legOrder.indices.contains(nextStop.legIndex) {
            legIndex = nextStop.legIndex
        }

        return nextStop
    }
    
    mutating func backtrackToPreviousStop() -> ResolvedStop? {
        guard let prevStop = previousStop else { return nil }
        stopIndex -= 1
        if legOrder.indices.contains(prevStop.legIndex) {
            legIndex = prevStop.legIndex
        }
        return prevStop
    }
    
    mutating func advanceToNextLeg() -> ResolvedLeg? {
        let nextIndex = legIndex + 1
        guard legOrder.indices.contains(nextIndex) else {
            return nil
        }
        
        legIndex = nextIndex
        return legOrder[legIndex]
    }

}

struct PredictionState: Equatable, Codable {
    let predictedStop:ResolvedStop
    let predictedStopType: PredictionTargetType
    var acceptableRouteIds: [String] = []
    var loadingState:PredictionLoadingState
    var arrivedTrains: [ArrivedTrain] = []
    var lastObservedPredictions: [TransitPrediction] = []
    
    mutating func cleanArrivedTrains(newPredictions: [TransitPrediction]) {
        let newTripIds = Set(newPredictions.compactMap { $0.tripId })
        for oldPrediction in lastObservedPredictions {
            guard let tripId = oldPrediction.tripId else { continue }
            if !newTripIds.contains(tripId) {
                let text = oldPrediction.display.lowercased()
                if ["1 min", "1m", "arriving", "arr", "brd", "boarding", "0 min", "stopped"].contains(text) {
                    if let vehicleId = oldPrediction.vehicleId {
                        print("JourneyEngine: Train \(vehicleId) arrived and dropped off predictions.")
                        arrivedTrains.append(ArrivedTrain(vehicleId: vehicleId, tripId: tripId, arrivedAt: Date()))
                    }
                }
            }
        }
        arrivedTrains.removeAll { Date().timeIntervalSince($0.arrivedAt) > 180 }
        lastObservedPredictions = newPredictions
    }
}

enum PredictionTargetType: String, Codable, Equatable {
    case boarding
    case transfer
}

enum PredictionLoadingState: Equatable, Codable {
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

struct ArrivedTrain: Equatable, Codable {
    let vehicleId: String
    let tripId: String
    let arrivedAt: Date
}

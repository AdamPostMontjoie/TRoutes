import Foundation

struct JourneyCommandValidator {
    static func reduce(
        state: inout JourneyState,
        command: JourneyCommand,
        surfaceQueue: [JourneyEngine.RecentlyDepartedVehicle]
    ) -> [JourneyEffect] {
        switch command {
        case let .executeEntry(stopId: id):
            if state.movementStatus == .enRoute && state.currentStop?.mbtaStopId == id {
                print("JourneyEngine accepted entry \(id)")
                return JourneyAction.arriveAtStop.reduce(state: &state)
            } else {
                print("JourneyEngine ignored entry \(id) current: \(state.currentStop?.mbtaStopId ?? "nil") status: \(state.movementStatus)")
                return []
            }
            
        case let .executeExit(stopId: id):
            if state.movementStatus == .atStop && state.currentStop?.mbtaStopId == id {
                print("JourneyEngine accepted exit \(id)")
                
                var effects: [JourneyEffect] = []
                
                if state.monitoringMode == .surface {
                    let recentVehicles = surfaceQueue.filter { Date().timeIntervalSince($0.timestamp) <= 60 }
                    if let recent = recentVehicles.last {
                        print("JourneyEngine: Surface geofence exit matched with recently departed vehicle \(recent.vehicleId). Reconciling.")
                        effects.append(.updateTrackedVehicle(vehicleId: recent.vehicleId, tripId: recent.tripId))
                        effects.append(.refreshTripTrackingData(tripId: recent.tripId))
                    } else {
                        print("JourneyEngine: Surface geofence exit with no recently departed vehicles in grace period. Keeping current tracked vehicle.")
                    }
                }
                
                effects.append(contentsOf: JourneyAction.departFromStop.reduce(state: &state))
                return effects
            } else {
                print("JourneyEngine ignored exit \(id) current: \(state.currentStop?.mbtaStopId ?? "nil") status: \(state.movementStatus)")
                return []
            }
            
        case let .approachingStop(stopId: id):
            if state.movementStatus == .enRoute,
               state.currentStop?.mbtaStopId == id {
                let userMessage = "Approaching \(state.currentStop?.stopName ?? id)"
                return [.sendNotification("Approaching \(id)", user: userMessage)]
            }
            return []
            
        case let .missedVehicle(stopId: id):
            print("JourneyEngine missedVehicle for \(id)")
            var effects: [JourneyEffect] = []
            effects.append(.sendNotification("Missed vehicle at \(id)", user: "Looks like you missed this train. Recalculating next departure..."))
            effects.append(.resetTrackingState)
            
            if state.currentStop?.mbtaStopId == id,
               state.movementStatus == .atStop,
               let currentStop = state.currentStop {
                state.pendingDepartureConfirmation = false
                state.movementStatus = .atStop
                state.predictionState = .loading(stopId: currentStop.mbtaStopId)
                
                effects.append(.monitorStop(currentStop))
                effects.append(.fetchPredictions(currentStop))
            } else if state.movementStatus == .enRoute {
                effects.append(contentsOf: JourneyAction.backtrackToStop.reduce(state: &state))
            } else {
                print("JourneyEngine ignored missedVehicle \(id) current: \(state.currentStop?.mbtaStopId ?? "nil") status: \(state.movementStatus)")
            }
            return effects
            
        case let .refreshTimes(stopId: id):
            if let currentStop = state.currentStop, currentStop.mbtaStopId == id {
                return JourneyAction.evaluatePredictionRefresh.reduce(state: &state)
            }
            return []
            
        case let .confirmDeparture(stopId: id):
            print("JourneyEngine confirmDeparture for \(id)")
            guard state.currentStop?.mbtaStopId == id,
                  state.movementStatus == .atStop else {
                return []
            }
            state.pendingDepartureConfirmation = true
            return JourneyAction.departFromStop.reduce(state: &state)
            
        case .locationAuthorizationDenied:
            return [.endRoute]
            
        case let .monitoringFailed(stopId: stopId, error: error):
            print("monitoring failed for \(stopId): \(error)")
            let isSurface = state.monitoringMode == .surface
            let userMessage = (isSurface && error == .locationUnknown) ? "GPS signal lost or inaccurate. Tracking may be degraded." : nil
            return [.sendNotification("monitoring failed for \(stopId): \(error)", user: userMessage)]
        }
    }
    
    static func handleDepartureConfirmation(
        state: inout JourneyState,
        boarded: Bool
    ) -> [JourneyEffect] {
        state.pendingDepartureConfirmation = false
        
        if boarded {
            if state.movementStatus == .atStop {
                return JourneyAction.departFromStop.reduce(state: &state)
            }
            return []
        }
        
        var effects: [JourneyEffect] = [.resetTrackingState]
        
        if state.movementStatus == .atStop,
           let currentStop = state.currentStop {
            state.predictionState = .loading(stopId: currentStop.mbtaStopId)
            effects.append(.monitorStop(currentStop))
            effects.append(.fetchPredictions(currentStop))
        } else {
            effects.append(contentsOf: JourneyAction.backtrackToStop.reduce(state: &state))
        }
        
        return effects
    }
}

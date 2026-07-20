import Foundation

enum JourneyCommand: Equatable {
    case executeEntry(stopId:String)//user has entered the stop
    case executeExit(stopId:String)//user has left the stop
    case missedVehicle(stopId: String)//we missed the train
    case confirmDeparture(stopId: String)//w
    case handleNewPredictions(predictionResults:[TransitPrediction])
    case refreshTimes(stopId: String, isUserInitiated: Bool)
    case locationAuthorizationDenied
    case monitoringFailed(stopId: String, error: locationError, message: String? = nil)
    case handleVehicleSearchResult(vehicleId: String, tripId: String)
}

///Determines JourneyCommand Validity, Runs JourneyAction, and emits JourneyEffects
struct JourneyCommandValidator {
    static func reduce(
        state: inout JourneyState,
        command: JourneyCommand
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
                if state.activeLegPrediction != nil {
                    if let recent = state.activeLegPrediction?.arrivedTrains.last {
                        print("JourneyEngine: Exit matched with arrived train \(recent.vehicleId).")
                        state.trackedVehicleId = recent.vehicleId
                        state.trackedTripId = recent.tripId
                        effects.append(.updateTrackedVehicle(vehicleId: recent.vehicleId, tripId: recent.tripId))
                        effects.append(.refreshTripPath(tripId: recent.tripId))
                    } else {
                        print("JourneyEngine: Exit with no arrived trains in queue. Keeping current tracked vehicle.")
                    }
                }
                
                
                effects.append(contentsOf: JourneyAction.departFromStop.reduce(state: &state))
                
                // If we exited without a tracked vehicle on surface, start searching
                if state.trackedVehicleId == nil && state.monitoringMode == .surface {
                    effects.append(.searchForVehicle)
                }
                
                return effects
            } else {
                print("JourneyEngine ignored exit \(id) current: \(state.currentStop?.mbtaStopId ?? "nil") status: \(state.movementStatus)")
                return []
            }
            
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
                state.activeLegPrediction = PredictionState(
                    predictedStop: currentStop,
                    predictedStopType: .boarding,
                    acceptableRouteIds: state.acceptableRouteIds(for: currentStop),
                    loadingState: .loading(stopId: currentStop.mbtaStopId)
                )
                
                effects.append(.monitorStop(currentStop))
                effects.append(.fetchPredictions)
            } else if state.movementStatus == .enRoute {
                effects.append(contentsOf: JourneyAction.backtrackToStop.reduce(state: &state))
            } else {
                print("JourneyEngine ignored missedVehicle \(id) current: \(state.currentStop?.mbtaStopId ?? "nil") status: \(state.movementStatus)")
            }
            return effects
        
        case let .handleNewPredictions(predictions):
            return JourneyAction.handleNewPredictions.reduce(state: &state, predictions:predictions)
            
            //determine to emit updatetrackedvehicle effect
        case let .refreshTimes(stopId: id, isUserInitiated: isUserInitiated):
            if let currentStop = state.currentStop, currentStop.mbtaStopId == id {
                return JourneyAction.evaluatePredictionRefresh.reduce(state: &state, isManual: isUserInitiated)
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
            
        case let .monitoringFailed(stopId: stopId, error: error, message: message):
            print("monitoring failed for \(stopId): \(error)\(message.map { " - \($0)" } ?? "")")
            let isSurface = state.monitoringMode == .surface
            let userMessage = (isSurface && error == .locationUnknown) ? "GPS signal lost or inaccurate. Tracking may be degraded." : nil
            let notificationMessage = if let message, !message.isEmpty {
                "monitoring failed for \(stopId): \(error) (\(message))"
            } else {
                "monitoring failed for \(stopId): \(error)"
            }
            return [.sendNotification(notificationMessage, user: userMessage)]
            
        case let .handleVehicleSearchResult(vehicleId, tripId):
            guard state.monitoringMode == .surface, state.trackedVehicleId == nil else { return [] }
            state.trackedVehicleId = vehicleId
            state.trackedTripId = tripId
            return [
                .updateTrackedVehicle(vehicleId: vehicleId, tripId: tripId),
                .refreshTripPath(tripId: tripId)
            ]
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
            state.activeLegPrediction = PredictionState(
                predictedStop: currentStop,
                predictedStopType: .boarding,
                acceptableRouteIds: state.acceptableRouteIds(for: currentStop),
                loadingState: .loading(stopId: currentStop.mbtaStopId)
            )
            effects.append(.monitorStop(currentStop))
            effects.append(.fetchPredictions)
        } else {
            effects.append(contentsOf: JourneyAction.backtrackToStop.reduce(state: &state))
        }
        
        return effects
    }
}

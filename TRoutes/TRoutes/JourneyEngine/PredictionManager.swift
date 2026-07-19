//
//  PredictionManager.swift
//  TRoutes
//

import Foundation
import ComposableArchitecture

actor PredictionManager {
    static let shared = PredictionManager()
    
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    
    var lastManualRefresh: Date?
    var lastPredictionFetchTime: Date?
    
    func setLastManualRefresh(_ date: Date) {
        lastManualRefresh = date
    }
    
    func fetchPredictions() async {
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        
        lastPredictionFetchTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            if let active = currentJourney.activeLegPrediction {
                group.addTask {
                    do {
                        let response = try await self.mbtaClient.fetchTransitTimes(active.predictedStop, active.acceptableRouteIds, .currentStopPrediction)
                        await self.handlePredictionSuccess(predictions: response, isTransfer: false)
                    } catch {
                        await self.handlePredictionFailure(error: error, isTransfer: false)
                    }
                }
            }
            //mutally exclusive so no need for task group
            if let transfer = currentJourney.transferLegPrediction {
                group.addTask {
                    do {
                        let response = try await self.mbtaClient.fetchTransitTimes(transfer.predictedStop, transfer.acceptableRouteIds, .transferPrediction)
                        await self.handlePredictionSuccess(predictions: response, isTransfer: true)
                    } catch {
                        await self.handlePredictionFailure(error: error, isTransfer: true)
                    }
                }
            }
        }
    }
    
    private func handlePredictionSuccess(predictions: [TransitPrediction], isTransfer: Bool) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard var targetPrediction = isTransfer ? freshJourney.transferLegPrediction : freshJourney.activeLegPrediction else { return }
        
        let times = predictions.map(\.display)
        if times.isEmpty {
            targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "No predictions available")
        } else {
            targetPrediction.loadingState = .loaded(stopId: targetPrediction.predictedStop.mbtaStopId, times: times)
            
            // Diff predictions to populate arrivedTrains queue
            targetPrediction.cleanArrivedTrains(newPredictions: predictions)
            
            // Track top vehicle for underground handoff
            if !isTransfer, targetPrediction.predictedStopType == .boarding {
                
                let trackedVehicleId = await JourneyEngine.shared.trackedVehicleId
                let isTrackedInPredictions = predictions.contains(where: { $0.vehicleId == trackedVehicleId })
                let isTrackedInArrived = targetPrediction.arrivedTrains.contains(where: { $0.vehicleId == trackedVehicleId })
                var currentTrackedStillValid = trackedVehicleId != nil && (isTrackedInPredictions || isTrackedInArrived)
                
                // Force swap if a DIFFERENT valid train physically arrived and dropped off the board before our tracked train
                if let justArrived = targetPrediction.arrivedTrains.last, justArrived.vehicleId != trackedVehicleId {
                    currentTrackedStillValid = false
                }
                
                if !currentTrackedStillValid {
                    var vehicleIdToTrack: String?
                    var tripIdToTrack: String?
                    
                    if let justArrived = targetPrediction.arrivedTrains.last {
                        vehicleIdToTrack = justArrived.vehicleId
                        tripIdToTrack = justArrived.tripId
                    } else if let firstValid = predictions.first(where: { $0.vehicleId != nil && $0.tripId != nil }) {
                        vehicleIdToTrack = firstValid.vehicleId
                        tripIdToTrack = firstValid.tripId
                    }
                    
                    if let vehicleIdToTrack, let tripIdToTrack {
                        await JourneyEngine.shared.updateTrackedVehicleIds(vehicleId: vehicleIdToTrack, tripId: tripIdToTrack)
                        
                        if freshJourney.monitoringMode == .underground {
                            print("JourneyEngine: Updating UGM with new tracked vehicle while at stop \(targetPrediction.predictedStop.mbtaStopId)")
                            await UndergroundManager.shared.setTrackedVehicle(
                                vehicleId: vehicleIdToTrack,
                                tripId: tripIdToTrack,
                                boardingStopId: targetPrediction.predictedStop.mbtaStopId,
                                waitToBoard: true,
                                stopLatitude: targetPrediction.predictedStop.latitude,
                                stopLongitude: targetPrediction.predictedStop.longitude,
                                isFirstStop: freshJourney.stopIndex == 0
                            )
                        }
                    }
                }
            }
        }
        
        if isTransfer {
            freshJourney.transferLegPrediction = targetPrediction
        } else {
            freshJourney.activeLegPrediction = targetPrediction
        }
        await JourneyEngine.shared.saveActiveJourneyAndPublish(freshJourney)
    }

    private func handlePredictionFailure(error: Error, isTransfer: Bool) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard var targetPrediction = isTransfer ? freshJourney.transferLegPrediction : freshJourney.activeLegPrediction else { return }
        
        if let mbtaError = error as? MBTAError, (mbtaError == .rateLimitDropped || mbtaError == .rateLimited) {
            if case .loading = targetPrediction.loadingState {
                targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "Rate limit reached. Try again.")
            } else {
                return
            }
        } else {
            targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "Cannot reach predictions")
        }
        
        if isTransfer {
            freshJourney.transferLegPrediction = targetPrediction
        } else {
            freshJourney.activeLegPrediction = targetPrediction
        }
        await JourneyEngine.shared.saveActiveJourneyAndPublish(freshJourney)
    }
}

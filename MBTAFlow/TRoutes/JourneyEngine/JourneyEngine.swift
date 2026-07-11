//
//  JourneyEngine.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/17/26.
//

import ComposableArchitecture
import CoreLocation

enum ManualEvent: Equatable {
    case nextStopTapped
    case atStopTapped
}

enum JourneyCommand: Equatable {
    case executeEntry(stopId:String)//user has entered the stop
    case executeExit(stopId:String)//user has left the stop
    case approachingStop(stopId: String)//user is nearing the stop
    case missedVehicle(stopId: String)//we missed the train
    case confirmDeparture(stopId: String)//w
    case refreshTimes(stopId: String)
    case locationAuthorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}


///Manages The Journey
actor JourneyEngine {

    ///Singleton
    static let shared = JourneyEngine()
    
    // MARK: - Dependencies & Properties
    
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.databaseClient) var databaseClient
    
    private let positionReconciler = PositionReconciler()
    
    //multiple queues to allow for widget later
    private var journeyUpdateContinuations: [UUID: AsyncStream<JourneyUpdate>.Continuation] = [:]
    
    private var locationListeningTask: Task<Void, Never>?
    private var undergroundListeningTask: Task<Void, Never>?
    private var predictionRefreshTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    private var lastManualRefresh: Date?
    private var lastPredictionFetchTime: Date?
    
    //underground fields
    private var matchedPath:MatchedLegPath?
    private var trackedVehicleId: String?
    private var trackedTripId: String?
    private var trackedBoardingStopId: String?
    
    // MARK: - Lifecycle & State Reconciliation
    
    //add state reconciliation checks
    func restoreActiveJourneyIfNeeded() async {
        guard let journey = userDefaultsClient.loadActiveJourney(),
              journey.currentStop != nil
        else { return }
        
        // Restore in-memory caching variables
        self.trackedVehicleId = journey.trackedVehicleId
        self.trackedTripId = journey.trackedTripId
        self.trackedBoardingStopId = journey.trackedBoardingStopId
        
        // Start location updates briefly to get a location anchor if needed
        var location = await RegionManager.shared.currentDeviceLocation
        if location == nil {
            print("JourneyEngine: Location is nil on boot. Waiting 1.5 seconds for GPS warm up...")
            try? await Task.sleep(for: .seconds(1.5))
            location = await RegionManager.shared.currentDeviceLocation
        }
        
        guard let location = location else {
            print("JourneyEngine: Unable to get location for reconciliation. Terminating journey.")
            await endRouteWithReconciliationFailure()
            return
        }
        
        do {
            let reconciledJourney = try await positionReconciler.reconcile(
                journey: journey,
                currentLocation: location,
                trackedVehicleId: trackedVehicleId
            )
            
            saveActiveJourneyAndPublish(reconciledJourney)
            await sendNotification(debug: "Journey Engine Reconciled Position Successfully")
            
            
            switch reconciledJourney.monitoringMode {
            case .surface:
                await startListeningToLocationEvents()
            case .underground:
                await startListeningToUndergroundEvents()
            }
            
            if let freshStop = reconciledJourney.currentStop {
                await monitorNextStop(stop: freshStop)
            }
            
        } catch PositionReconciler.ReconcileError.timeout {
            print("JourneyEngine: Journey state expired (30min timeout). Dumping silently.")
            await endRoute()
        } catch {
            print("JourneyEngine: PositionReconciler failed to reconcile journey state. Terminating journey. Error: \(error)")
            await endRouteWithReconciliationFailure()
        }
    }
    
    private func endRouteWithReconciliationFailure() async {
        for continuation in journeyUpdateContinuations.values {
            continuation.yield(.journeyTerminated(.trackingReconciliationFailed))
        }
        await endRoute()
    }
    
    // MARK: - Stream Listeners
    
    func startListeningToLocationEvents() async {
        guard locationListeningTask == nil else { return }
        let stream = await RegionManager.shared.makeEventStream()
        
        locationListeningTask = Task {
            for await event in stream {
                await self.ValidateJourneyCommand(event)
            }
            self.locationEventStreamDidFinish()
        }
    }
    
    func startListeningToUndergroundEvents() async {
        guard undergroundListeningTask == nil else { return }
        print("JourneyEngine start underground listener")
        let stream = await UndergroundManager.shared.makeEventStream()

        undergroundListeningTask = Task {
            for await event in stream {
                print("JourneyEngine received underground command: \(event)")
                await self.ValidateJourneyCommand(event)
            }
            self.undergroundEventStreamDidFinish()
        }
    }
    
    private func locationEventStreamDidFinish() {
        locationListeningTask = nil
    }
    
    private func undergroundEventStreamDidFinish() {
        undergroundListeningTask = nil
    }
    
    func requestAuthorization() async {
        await RegionManager.shared.requestLocationAuthorization()
    }
    
    private func removeJourneyUpdateContinuation(id: UUID) {
        journeyUpdateContinuations.removeValue(forKey: id)
    }

    ///Streams active journey to UI
    func makeJourneyUpdateStream() async -> AsyncStream<JourneyUpdate> {
        let (stream, continuation) = AsyncStream<JourneyUpdate>.makeStream()
        let id = UUID()
        self.journeyUpdateContinuations[id] = continuation
        
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeJourneyUpdateContinuation(id: id)
            }
        }
        
        // Hydrate UI immediately if there is a saved journey running
        if let journey = userDefaultsClient.loadActiveJourney() {
            continuation.yield(.activeJourneyChanged(journey))
        }
        
        return stream
    }
    
    ///Starts the route
    func beginRoute(route:ResolvedUserRoute) async {
        let journey = JourneyState(route: route)
        saveActiveJourneyAndPublish(journey)
        let destinationName = route.legs.last?.endStop.stopName ?? "your destination"
        await sendNotification(debug: "Tracking started", user: "Tracking started for your trip to \(destinationName)")
        if let firstStop = journey.currentStop {
            if firstStop.monitoringMode == .surface {
                await startListeningToLocationEvents()
            } else {
                await startListeningToUndergroundEvents()
            }
            await monitorNextStop(stop: firstStop)
            await self.fetchPredictions()
        }
    }
    
    // MARK: - Action Validation (Inputs)
    
    //this will handle both widget and in app i think
    func manualEventValidator(_ event:ManualEvent) async{
        guard let currentStop = userDefaultsClient.loadActiveJourney()?.currentStop else { return }
        switch event {
        case .atStopTapped:
            await self.ValidateJourneyCommand(JourneyCommand.executeEntry(stopId: currentStop.mbtaStopId))
        case .nextStopTapped:
            await self.ValidateJourneyCommand(JourneyCommand.executeExit(stopId: currentStop.mbtaStopId))
        }
        //cases for manual missed stop and confirm train TBA
    }
    
    //did we already receive this valid command from a different source and make the change?
    func ValidateJourneyCommand(_ event:JourneyCommand) async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        
        let effects = JourneyCommandValidator.reduce(
            state: &currentJourney,
            command: event
        )
        saveActiveJourneyAndPublish(currentJourney)
        await runJourneyEffects(effects)
    }
    
    func handleDepartureConfirmation(boarded: Bool) async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let effects = JourneyCommandValidator.handleDepartureConfirmation(state: &currentJourney, boarded: boarded)
        saveActiveJourneyAndPublish(currentJourney)
        await runJourneyEffects(effects)
    }
    
    // MARK: - Journey Effects (Outputs)
    
    private func runJourneyEffects(_ effects: [JourneyEffect]) async {
        for effect in effects {
            switch effect {
            case let .monitorStop(stop):
                print("JourneyEngine effect: registerRegion for \(stop.mbtaStopId)")
                await monitorNextStop(stop: stop)
                
            case .fetchPredictions:
                print("JourneyEngine effect: fetchPredictions")
                await fetchPredictions()
                
            case let .sendNotification(debug, user):
                print("JourneyEngine effect: sendNotification - \(debug)")
                await sendNotification(debug: debug, user: user)
                
            case let .switchMonitoringMode(mode):
                await switchMonitoringMode(newMode: mode)
                
            case .endRoute:
                print("JourneyEngine effect: endRoute")
                await endRoute()
                
            case let .updateTrackedVehicle(vehicleId, tripId):
                print("JourneyEngine effect: updateTrackedVehicle to \(vehicleId ?? "nil")")
                self.trackedVehicleId = vehicleId
                self.trackedTripId = tripId
                
            case .resetTrackingState:
                print("JourneyEngine effect: resetTrackingState")
                self.trackedVehicleId = nil
                self.trackedTripId = nil
                self.matchedPath = nil
                
            case let .refreshTripPath(tripId):
                print("JourneyEngine effect: refreshTripTrackingData for \(tripId)")
                await self.refreshTripPath(tripId: tripId)
            }
        }
    }
    
    // This needs to execute before register region every time.
    // we can just stop the current session, as the registration will be simple
    func switchMonitoringMode(newMode: MonitoringMode) async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        print("JourneyEngine switchMonitoringMode \(newMode)")
        currentJourney.monitoringMode = newMode
        switch newMode {
        case .surface:
            //end UGM
            await UndergroundManager.shared.stopFunction()
            //start RGM
            print("surface monitoring")
            await startListeningToLocationEvents()
        case .underground:
            //end RGM
            await RegionManager.shared.stopFunction()
            //start UGM
            print("underground monitoring")
            await startListeningToUndergroundEvents()
        }
        saveActiveJourneyAndPublish(currentJourney)
    }

    func monitorNextStop(stop:ResolvedStop) async {
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let mode = currentJourney.monitoringMode
        print("JourneyEngine monitorNextStop stop: \(stop.mbtaStopId) mode: \(mode) role: \(stop.journeyRole)")
        switch mode {
        case .surface:
            print("surface monitoring")
            await RegionManager.shared.registerRegion(
                for: stop,
                previousMonitoringMode: currentJourney.previousStop?.monitoringMode
            )
        case .underground:
            print("underground monitoring")
            await UndergroundManager.shared.startSession()
            
            let isWaitingToBoard = stop.journeyRole == .boarding
            if let trackedVehicleId = currentJourney.trackedVehicleId,
               let trackedTripId = currentJourney.trackedTripId {
                print("JourneyEngine set UGM vehicle: \(trackedVehicleId) trip: \(trackedTripId) stop: \(stop.mbtaStopId)")
                await UndergroundManager.shared.setTrackedVehicle(
                    vehicleId: trackedVehicleId,
                    tripId: trackedTripId,
                    boardingStopId: stop.mbtaStopId,
                    waitToBoard: isWaitingToBoard,
                    stopLatitude: stop.latitude,
                    stopLongitude: stop.longitude,
                    isFirstStop: currentJourney.stopIndex == 0
                )
            } else {
                print("JourneyEngine underground tracking not ready for \(stop.mbtaStopId) - no tracked vehicle")
            }
        }
    }
    
    // MARK: - MBTA API & Predictions
    
    func manualRefreshPredictions() async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }

        // Debounce: prevent spamming refresh
        let now = Date()
        if let last = lastManualRefresh, now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastManualRefresh = now
        
        if var activePrediction = currentJourney.activeLegPrediction {
            activePrediction.loadingState = .loading(stopId: activePrediction.predictedStop.mbtaStopId)
            currentJourney.activeLegPrediction = activePrediction
        }
        if var transferPrediction = currentJourney.transferLegPrediction {
            transferPrediction.loadingState = .loading(stopId: transferPrediction.predictedStop.mbtaStopId)
            currentJourney.transferLegPrediction = transferPrediction
        }
        
        saveActiveJourneyAndPublish(currentJourney)
        
        await fetchPredictions()
    }
    
    
    private func fetchPredictions() async {
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        
        lastPredictionFetchTime = Date()
        
        async let activeResult: Result<[TransitPrediction], Error>? = {
            if let active = currentJourney.activeLegPrediction {
                do {
                    let response = try await mbtaClient.fetchTransitTimes(active.predictedStop, .currentStopPrediction)
                    return .success(response)
                } catch {
                    return .failure(error)
                }
            }
            return nil
        }()
        
        async let transferResult: Result<[TransitPrediction], Error>? = {
            if let transfer = currentJourney.transferLegPrediction {
                do {
                    let response = try await mbtaClient.fetchTransitTimes(transfer.predictedStop, .transferPrediction)
                    return .success(response)
                } catch {
                    return .failure(error)
                }
            }
            return nil
        }()
        
        let (active, transfer) = await (activeResult, transferResult)
        
        if let active = active {
            await handlePredictionResult(result: active, isTransfer: false)
        }
        if let transfer = transfer {
            await handlePredictionResult(result: transfer, isTransfer: true)
        }
    }
    
    
    private func handlePredictionResult(result: Result<[TransitPrediction], Error>, isTransfer: Bool) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        
        guard var targetPrediction = isTransfer ? freshJourney.transferLegPrediction : freshJourney.activeLegPrediction else { return }
        
        switch result {
        case let .success(predictionResults):
            let times = predictionResults.map(\.display)
            if times.isEmpty {
                targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "No predictions available")
            } else {
                targetPrediction.loadingState = .loaded(stopId: targetPrediction.predictedStop.mbtaStopId, times: times)
                
                // Diff predictions to populate arrivedTrains queue
                targetPrediction.cleanArrivedTrains(newPredictions: predictionResults)
                
                // Track top vehicle for underground handoff
                if !isTransfer, targetPrediction.predictedStopType == .boarding, freshJourney.movementStatus == .atStop {
                    
                    let isTrackedInPredictions = predictionResults.contains(where: { $0.vehicleId == trackedVehicleId })
                    let isTrackedInArrived = targetPrediction.arrivedTrains.contains(where: { $0.vehicleId == trackedVehicleId })
                    let currentTrackedStillValid = trackedVehicleId != nil && (isTrackedInPredictions || isTrackedInArrived)
                    
                    if !currentTrackedStillValid, let firstValid = predictionResults.first(where: { $0.vehicleId != nil && $0.tripId != nil }) {
                        trackedVehicleId = firstValid.vehicleId
                        trackedTripId = firstValid.tripId
                        
                        if freshJourney.monitoringMode == .underground {
                            print("JourneyEngine: Updating UGM with new tracked vehicle while at stop \(targetPrediction.predictedStop.mbtaStopId)")
                            await UndergroundManager.shared.setTrackedVehicle(
                                vehicleId: firstValid.vehicleId!,
                                tripId: firstValid.tripId!,
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
        case .failure(let error):
            if let mbtaError = error as? MBTAError, (mbtaError == .rateLimitDropped || mbtaError == .rateLimited) {
                if case .loading = targetPrediction.loadingState {
                    targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "Rate limit reached. Try again.")
                } else {
                    return
                }
            } else {
                targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "Cannot reach predictions")
            }
        }
        
        if isTransfer {
            freshJourney.transferLegPrediction = targetPrediction
        } else {
            freshJourney.activeLegPrediction = targetPrediction
        }
        saveActiveJourneyAndPublish(freshJourney)
    }
    

    private func refreshTripPath(tripId:String) async  {
        do {
            let tripTrackingData = try await mbtaClient.fetchTripTrackingData(tripId, .patternMatching)
            // we need a new path once we get new trip data
            updateLivePath(liveTripPath: tripTrackingData)
            
        } catch {
            handleVehicleFetchError(error: error)
        }
    }
    
    private func handleVehicleFetchError(error: Error){
        print("this is where we could deal with internet issues, like timeout errors or api issues")
    }
    
    private func updateLivePath(liveTripPath:LiveTripPath) {
        guard let currentLeg = userDefaultsClient.loadActiveJourney()?.currentLeg else { return }
        guard matchedPath?.matches(leg: currentLeg, tripId: liveTripPath.tripId) != true else { return }
        
        matchedPath = MatchedLegPath( leg: currentLeg,tripPath: liveTripPath)
    }
    
    // MARK: - State Publishing Helpers
    
    private func managePredictionTimer(for journey: JourneyState) {
        if journey.activeLegPrediction != nil || journey.transferLegPrediction != nil {
            if predictionRefreshTask == nil {
                startPredictionRefreshTimer()
            }
        } else {
            stopPredictionRefreshTimer()
        }
    }
    
    private func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        var journeyToSave = journey
        journeyToSave.trackedVehicleId = self.trackedVehicleId
        journeyToSave.trackedTripId = self.trackedTripId
        journeyToSave.trackedBoardingStopId = self.trackedBoardingStopId
        journeyToSave.timeSaved = Date()
        
        userDefaultsClient.saveActiveJourney(journeyToSave)
        managePredictionTimer(for: journeyToSave)
        
        for continuation in journeyUpdateContinuations.values {
            continuation.yield(.activeJourneyChanged(journeyToSave))
        }
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        stopPredictionRefreshTimer()
        for continuation in journeyUpdateContinuations.values {
            continuation.yield(.activeJourneyChanged(nil))
        }
    }
    
    func sendNotification(debug: String, user: String? = nil) async {
        await notificationsClient.debugNotification(debug)
        if let user = user {
            await notificationsClient.userNotification(user)
        }
    }
    
    func endRoute() async {
        clearActiveJourneyAndPublish()
        stopPredictionRefreshTimer()
        matchedPath = nil
        trackedVehicleId = nil
        trackedTripId = nil
        trackedBoardingStopId = nil
        await RegionManager.shared.killManager()
        await UndergroundManager.shared.killManager()
    }
    
    // MARK: - Timers
    
    private func startPredictionRefreshTimer() {
        stopPredictionRefreshTimer()
        predictionRefreshTask = Task {
            while !Task.isCancelled {
                let now = Date()
                let timeSinceLastFetch = now.timeIntervalSince(lastPredictionFetchTime ?? .distantPast)
                let timeToWait = max(1.0, 15.0 - timeSinceLastFetch)
                
                try? await Task.sleep(for: .seconds(timeToWait))
                
                guard !Task.isCancelled else { break }
                
                if let journey = userDefaultsClient.loadActiveJourney(), let stop = journey.currentStop {
                    await ValidateJourneyCommand(.refreshTimes(stopId: stop.mbtaStopId))
                }
            }
        }
    }
    
    private func stopPredictionRefreshTimer() {
        predictionRefreshTask?.cancel()
        predictionRefreshTask = nil
    }
    
}

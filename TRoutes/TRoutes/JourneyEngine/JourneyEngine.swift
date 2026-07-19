//
//  JourneyEngine.swift
//  TRoutes
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
    case missedVehicle(stopId: String)//we missed the train
    case confirmDeparture(stopId: String)//w
    case refreshTimes(stopId: String)
    case locationAuthorizationDenied
    case monitoringFailed(stopId: String, error: locationError, message: String? = nil)
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
    
    //monitoring mode
    private var monitoringMode:MonitoringMode?
    
    //underground fields
    public var matchedPath:MatchedLegPath?
    internal var trackedVehicleId: String?
    internal var trackedTripId: String?
    public var trackedBoardingStopId: String?
    
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
        var location = await SurfaceManager.shared.currentDeviceLocation
        if location == nil {
            print("JourneyEngine: Location is nil on boot. Waiting 1.5 seconds for GPS warm up...")
            try? await Task.sleep(for: .seconds(1.5))
            location = await SurfaceManager.shared.currentDeviceLocation
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
            
            await LiveActivityManager.shared.startListening()
            
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
        let stream = await SurfaceManager.shared.makeEventStream()
        
        locationListeningTask = Task {
            for await event in stream {
                await self.validateJourneyCommand(event)
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
                await self.validateJourneyCommand(event)
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
        await SurfaceManager.shared.requestLocationAuthorization()
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
        
        await LiveActivityManager.shared.startListening()
    }
    
    // MARK: - Action Validation (Inputs)
    
    //this will handle both widget and in app i think
    func manualEventValidator(_ event:ManualEvent) async{
        guard let currentStop = userDefaultsClient.loadActiveJourney()?.currentStop else { return }
        switch event {
        case .atStopTapped:
            await self.validateJourneyCommand(JourneyCommand.executeEntry(stopId: currentStop.mbtaStopId))
        case .nextStopTapped:
            await self.validateJourneyCommand(JourneyCommand.executeExit(stopId: currentStop.mbtaStopId))
        }
        //cases for manual missed stop and confirm train TBA
    }
    
    //did we already receive this valid command from a different source and make the change?
    func validateJourneyCommand(_ event:JourneyCommand) async {
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
                if tripId != self.matchedPath?.tripId {
                    await self.updateLivePath(tripId: tripId)
                }
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
            await SurfaceManager.shared.stopFunction()
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
            await SurfaceManager.shared.registerRegion(
                for: stop,
                previousMonitoringMode: currentJourney.previousStop?.monitoringMode
            )
        case .underground:
            print("underground monitoring")
            await UndergroundManager.shared.startSession()
            
            let isWaitingToBoard = stop.journeyRole == .boarding
            
            let trackedVehicleId = currentJourney.trackedVehicleId
            let trackedTripId = currentJourney.trackedTripId
            print("JourneyEngine set UGM vehicle: \(trackedVehicleId ?? "nil") trip: \(trackedTripId ?? "nil") stop: \(stop.mbtaStopId)")
            await UndergroundManager.shared.setTrackedVehicle(
                vehicleId: trackedVehicleId,
                tripId: trackedTripId,
                boardingStopId: stop.mbtaStopId,
                waitToBoard: isWaitingToBoard,
                stopLatitude: stop.latitude,
                stopLongitude: stop.longitude
            )
        }
    }
    
    // MARK: - MBTA API & Predictions
    
    func manualRefreshPredictions() async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }

        // Debounce: prevent spamming refresh
        let now = Date()
        if let last = self.lastManualRefresh, now.timeIntervalSince(last) < 2.0 {
            return
        }
        self.lastManualRefresh = now
        
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
        let isTransfer = currentJourney.activeLegPrediction == nil && currentJourney.transferLegPrediction != nil
        let currentPredictionState = isTransfer ? currentJourney.transferLegPrediction : currentJourney.activeLegPrediction
        guard let currentPredictionState else { return }
        do {
            let results = try await PredictionManager.shared.fetchPredictionsWithFallback(for: currentPredictionState, requestType: .currentStopPrediction)
            await handlePredictionResults(predictionResults: results, isTransfer: isTransfer)
        } catch {
            handleVehicleFetchError(error: error)
        }
        
    }
    
    private func handlePredictionResults(predictionResults: [TransitPrediction], isTransfer: Bool) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard var targetPrediction = isTransfer ? freshJourney.transferLegPrediction : freshJourney.activeLegPrediction else { return }
        
        let times = predictionResults.map(\.display)
        
        if times.isEmpty {
            targetPrediction.loadingState = .unavailable(stopId: targetPrediction.predictedStop.mbtaStopId, message: "No times available")
        } else {
            targetPrediction.loadingState = .loaded(stopId: targetPrediction.predictedStop.mbtaStopId, times: times)
            
            // Diff predictions to populate arrivedTrains queue
            targetPrediction.cleanArrivedTrains(newPredictions: predictionResults)
            
            // Track top vehicle for underground handoff
            if !isTransfer, targetPrediction.predictedStopType == .boarding {
                await updateVehicleTracking(targetPrediction:targetPrediction, predictionResults:predictionResults)
            }
        }
        
        if isTransfer {
            freshJourney.transferLegPrediction = targetPrediction
        } else {
            freshJourney.activeLegPrediction = targetPrediction
        }
        self.saveActiveJourneyAndPublish(freshJourney)
    }
    
    private func updateVehicleTracking(targetPrediction: PredictionState, predictionResults: [TransitPrediction]) async {
        let trackedVehicleId = self.trackedVehicleId
        var currentTrackedStillValid = trackedVehicleId != nil //Our current train needs to change
        let firstReturned = predictionResults.first(where: { $0.vehicleId != nil && $0.tripId != nil })
            
        //We're tracking a train, and one has just arrived
        if !targetPrediction.arrivedTrains.isEmpty {
            // Force swap if a valid train physically arrived and dropped off the board before our tracked train.
            if let justArrived = targetPrediction.arrivedTrains.last, justArrived.vehicleId != trackedVehicleId {
                currentTrackedStillValid = false
                self.trackedVehicleId = justArrived.vehicleId
                self.trackedTripId = justArrived.tripId
            }
        }
        else {
            //Update the first train to be the first one in predictions in case that's changed
            if firstReturned?.vehicleId != trackedVehicleId {
                self.trackedVehicleId = firstReturned?.vehicleId
                self.trackedTripId = firstReturned?.tripId
                currentTrackedStillValid = false
            }
        }
        
        //update UGM if we aren't tracking proper train anymore
        if !currentTrackedStillValid && self.monitoringMode == .underground  {
            let vehicleIdToTrack = self.trackedVehicleId
            let tripIdToTrack = self.trackedTripId
            
            await UndergroundManager.shared.setTrackedVehicle(
                vehicleId: vehicleIdToTrack,
                tripId: tripIdToTrack,
                boardingStopId: targetPrediction.predictedStop.mbtaStopId,
                waitToBoard: true,
                stopLatitude: targetPrediction.predictedStop.latitude,
                stopLongitude: targetPrediction.predictedStop.longitude
            )
        }
    }
    
    private func handleVehicleFetchError(error: Error){
        //TODO: do we need a loading state on the Journey itself? Right now the UI listens to active prediction's state. But what if tracking drops? Need to signify it's disconnected. Or is tracking being nil enough?
        print("JourneyEngine error fetching vehicle \(error.localizedDescription)")
    }
    
    private func updateLivePath(tripId:String) async {
        do {
            let liveTripPath = try await mbtaClient.fetchTripPathData(tripId, .patternMatching)
            guard let currentLeg = userDefaultsClient.loadActiveJourney()?.currentLeg else { return }
            matchedPath = MatchedLegPath( leg: currentLeg,tripPath: liveTripPath)
        } catch {
            handleVehicleFetchError(error: error)
        }
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
    
    internal func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        var journeyToSave = journey
        //update JourneyState before saving
        journeyToSave.trackedVehicleId = self.trackedVehicleId
        journeyToSave.trackedTripId = self.trackedTripId
        journeyToSave.trackedBoardingStopId = self.trackedBoardingStopId
        journeyToSave.timeSaved = Date()
        
        //update Journey Engine state for easy of use
        self.monitoringMode = journeyToSave.monitoringMode
    
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
        await SurfaceManager.shared.killManager()
        await UndergroundManager.shared.killManager()
        await LiveActivityManager.shared.endActivity()
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
                    await validateJourneyCommand(.refreshTimes(stopId: stop.mbtaStopId))
                }
            }
        }
    }
    
    private func stopPredictionRefreshTimer() {
        predictionRefreshTask?.cancel()
        predictionRefreshTask = nil
    }
    
}

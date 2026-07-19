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
    
    //journey
    private var activeJourney:JourneyState?
    
    
    
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
        guard let currentStop = self.activeJourney?.currentStop else { return }
        switch event {
        case .atStopTapped:
            await self.validateJourneyCommand(JourneyCommand.executeEntry(stopId: currentStop.mbtaStopId))
        case .nextStopTapped:
            await self.validateJourneyCommand(JourneyCommand.executeExit(stopId: currentStop.mbtaStopId))
        }
        //cases for manual missed stop and confirm train TBA
    }
    
    //Receives commands that will update state and runs effects
    func validateJourneyCommand(_ event:JourneyCommand) async {
        guard var currentJourney = self.activeJourney else { return }
        var mutatedJourney = currentJourney
        let effects = JourneyCommandValidator.reduce(
            state: &mutatedJourney,
            command: event
        )
        // save if state changed
        if mutatedJourney != currentJourney {
            saveActiveJourneyAndPublish(mutatedJourney)
        }
       
        await runJourneyEffects(effects)
    }
    
    func handleDepartureConfirmation(boarded: Bool) async {
        guard var currentJourney = self.activeJourney else { return }
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
                guard let targetPrediction = self.activeJourney?.currentPredictionState, self.activeJourney?.monitoringMode == .underground else {
                    return
                }
                print("JourneyEngine set UGM vehicle: \(vehicleId ?? "nil") trip: \(tripId ?? "nil")")
                await UndergroundManager.shared.setTrackedVehicle(
                    vehicleId: vehicleId,
                    tripId: tripId,
                    boardingStopId: targetPrediction.predictedStop.mbtaStopId,
                    waitToBoard: targetPrediction.predictedStopType == .boarding,
                    stopLatitude: targetPrediction.predictedStop.latitude,
                    stopLongitude: targetPrediction.predictedStop.longitude
                )
                
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
    
    //Switch Location Manager
    func switchMonitoringMode(newMode: MonitoringMode) async {
        print("JourneyEngine switchMonitoringMode \(newMode)")
        switch newMode {
        case .surface:
            //end UGM
            await UndergroundManager.shared.stopFunction()
            //start RGM
            await startListeningToLocationEvents()
        case .underground:
            //end RGM
            await SurfaceManager.shared.stopFunction()
            //start UGM
            await startListeningToUndergroundEvents()
        }
    }

    func monitorNextStop(stop:ResolvedStop) async {
        guard let currentJourney = self.activeJourney else { return }
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
            
            await UndergroundManager.shared.setTrackedVehicle(
                vehicleId: currentJourney.trackedVehicleId,
                tripId: currentJourney.trackedTripId,
                boardingStopId: stop.mbtaStopId,
                waitToBoard: stop.journeyRole == .boarding,
                stopLatitude: stop.latitude,
                stopLongitude: stop.longitude
            )
        }
    }
    
    // MARK: - MBTA API & Predictions
    
    func manualRefreshPredictions() async {
        guard let stopId = self.activeJourney?.currentStop?.mbtaStopId else { return }

        // Debounce: prevent spamming refresh
        let now = Date()
        if let last = self.lastManualRefresh, now.timeIntervalSince(last) < 2.0 {
            return
        }
        self.lastManualRefresh = now
        
        await self.validateJourneyCommand(.refreshTimes(stopId: stopId, isUserInitiated: true))
    }
    
    private func fetchPredictions() async {
        lastPredictionFetchTime = Date()
        
        guard let currentPredictionState = self.activeJourney?.currentPredictionState else { return }
        do {
            let results = try await PredictionManager.shared.fetchPredictionsWithFallback(for: currentPredictionState, requestType: .currentStopPrediction)
            await validateJourneyCommand(.handleNewPredictions(predictionResults: results))
        } catch {
            handleVehicleFetchError(error: error)
        }
    }
    
    private func handleVehicleFetchError(error: Error){
        //TODO: do we need a loading state on the Journey itself? Right now the UI listens to active prediction's state. But what if tracking drops? Need to signify it's disconnected. Or is tracking being nil enough?
        print("JourneyEngine error fetching vehicle \(error.localizedDescription)")
    }
    
    private func updateLivePath(tripId:String) async {
        do {
            let liveTripPath = try await mbtaClient.fetchTripPathData(tripId, .patternMatching)
            guard let currentLeg = self.activeJourney?.currentLeg else { return }
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
        journeyToSave.timeSaved = Date()
        
        //update Journey Engine observable state for ease of use
        self.activeJourney = journeyToSave
    
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
                
                if let journey = self.activeJourney, let stop = journey.currentStop {
                    await validateJourneyCommand(.refreshTimes(stopId: stop.mbtaStopId, isUserInitiated: false))
                }
            }
        }
    }
    
    private func stopPredictionRefreshTimer() {
        predictionRefreshTask?.cancel()
        predictionRefreshTask = nil
    }
    
}

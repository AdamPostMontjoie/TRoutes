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
    private var motionListeningTask: Task<Void, Never>?
    private var timingRefreshTask: Task<Void, Never>?
    private var isVehicleSearchActive = false
    private var loadingTask: Task<Void, Never>?
    private var routeEndTimerTask: Task<Void, Never>?
    private var lastManualRefresh: Date?
    private var lastTimingRefreshTime: Date?
    
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

        await StopLiveActivityManager.shared.end()
        
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
                if let stop = reconciledJourney.currentStop, reconciledJourney.movementStatus == .atStop {
                    await startListeningToMotionEvents(stop: stop)
                }
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
        let stream = await SurfaceManager.shared.makeCommandStream()
        
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
        let stream = await UndergroundManager.shared.makeCommandStream()

        undergroundListeningTask = Task {
            for await event in stream {
                print("JourneyEngine received underground command: \(event)")
                await self.validateJourneyCommand(event)
            }
            self.undergroundEventStreamDidFinish()
        }
    }
    
    func startListeningToMotionEvents(stop: ResolvedStop) async {
        guard stop.journeyRole == .boarding else { return }
        guard motionListeningTask == nil else { return }
        print("JourneyEngine start motion listener")
        let stream = await MotionManager.shared.makeCommandStream()

        motionListeningTask = Task {
            await MotionManager.shared.startCommands(stopId: stop.mbtaStopId)
            for await event in stream {
                print("JourneyEngine received motion command: \(event)")
                await self.validateJourneyCommand(event)
            }
            self.motionEventStreamDidFinish()
        }
    }
    
    private func locationEventStreamDidFinish() {
        locationListeningTask = nil
    }
    
    private func undergroundEventStreamDidFinish() {
        undergroundListeningTask = nil
    }
    
    private func motionEventStreamDidFinish() {
        motionListeningTask = nil
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
        await StopLiveActivityManager.shared.end()
        let journey = JourneyState(route: route)
        saveActiveJourneyAndPublish(journey)
        let destinationName = route.legs.last?.endStop.stopName ?? "your destination"
        await sendNotification(debug: "Tracking started", user: "Tracking started for your trip to \(destinationName)")
        if let firstStop = journey.currentStop {
            if firstStop.monitoringMode == .surface {
                await startListeningToLocationEvents()
            } else {
                await startListeningToUndergroundEvents()
                await startListeningToMotionEvents(stop: firstStop)
            }
            await monitorNextStop(stop: firstStop)
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
        guard let currentJourney = self.activeJourney else { return }
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
                
            case .updateJourneyTiming:
                print("JourneyEngine effect: updateJourneyTiming")
                lastTimingRefreshTime = Date()
                // Timing is advisory. Do not hold up tracking-critical effects
                // while its network snapshot is being collected.
                Task { await self.fetchJourneyTiming() }
                
            case let .sendNotification(debug, user):
                print("JourneyEngine effect: sendNotification - \(debug)")
                await sendNotification(debug: debug, user: user)
                
            case let .switchMonitoringMode(mode):
                await switchMonitoringMode(newMode: mode)
                
            case let .scheduleEndRoute(seconds):
                print("JourneyEngine effect: scheduleEndRoute in \(seconds)s")
                startRouteEndTimer(seconds: seconds)
                
            case .endRoute:
                print("JourneyEngine effect: endRoute")
                await endRoute()
            
            case let .updateTrackedVehicle(vehicleId, tripId):
                if vehicleId != nil {
                    stopVehicleSearch()
                }
                guard self.activeJourney?.monitoringMode == .underground else {
                    continue
                }
                guard let targetStop = self.activeJourney?.currentStop else {
                    continue
                }
                let waitToBoard = targetStop.journeyRole == .boarding || targetStop.journeyRole == .transfer(overlapsNext:true)
                
                print("JourneyEngine set UGM vehicle: \(vehicleId ?? "nil") trip: \(tripId ?? "nil") stop: \(targetStop.mbtaStopId)")
                await UndergroundManager.shared.setTrackedVehicle(
                    vehicleId: vehicleId,
                    tripId: tripId,
                    acceptableStopIds: targetStop.acceptableStopIds,
                    waitToBoard: waitToBoard,
                    stopLatitude: targetStop.latitude,
                    stopLongitude: targetStop.longitude
                )
                
            case .resetTrackingState:
                self.trackedVehicleId = nil
                self.trackedTripId = nil
                self.matchedPath = nil
                
            case let .refreshTripPath(tripId):
                if tripId != self.matchedPath?.tripId {
                    await self.updateLivePath(tripId: tripId)
                }

            case .searchForVehicle:
                print("JourneyEngine effect: searchForVehicle")
                startVehicleSearch()
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
            await MotionManager.shared.stopCommands()
            //start RGM
            await startListeningToLocationEvents()
        case .underground:
            //end RGM
            await SurfaceManager.shared.stopFunction()
            //start UGM
            await startListeningToUndergroundEvents()
            if let stop = activeJourney?.currentStop {
                await startListeningToMotionEvents(stop: stop)
            }
        }
    }

    func monitorNextStop(stop:ResolvedStop) async {
        guard let currentJourney = self.activeJourney else { return }
        let mode = currentJourney.monitoringMode
        let isAtStop = currentJourney.movementStatus == .atStop
        print("JourneyEngine monitorNextStop stop: \(stop.mbtaStopId) mode: \(mode) role: \(stop.journeyRole)")
        switch mode {
        case .surface:
            print("surface monitoring")
            await SurfaceManager.shared.registerRegion(
                for: stop,
                previousMonitoringMode: currentJourney.previousStop?.monitoringMode,
                isAlreadyAtStop: isAtStop
            )
        case .underground:
            print("underground monitoring")
            await UndergroundManager.shared.startSession()
            
            if isAtStop && (stop.journeyRole == .boarding) {
                await startListeningToMotionEvents(stop: stop)
            } else {
                await MotionManager.shared.stopCommands()
                motionListeningTask?.cancel()
                motionListeningTask = nil
            }
            
            await UndergroundManager.shared.setTrackedVehicle(
                vehicleId: currentJourney.trackedVehicleId,
                tripId: currentJourney.trackedTripId,
                acceptableStopIds: stop.acceptableStopIds,
                waitToBoard: stop.journeyRole == .boarding,
                stopLatitude: stop.latitude,
                stopLongitude: stop.longitude
            )
            
            //MARK: Terminus Band Aid
            if (stop.transitType == .commuterRail || stop.stopName == "Alewife" || stop.stopName == "Forest Hills")  && isAtStop {
                print("Commuter rail band-aid: registering surface backup region on entry")
                await startListeningToLocationEvents()
                await SurfaceManager.shared.registerRegion(
                    for: stop,
                    previousMonitoringMode: currentJourney.previousStop?.monitoringMode,
                    isAlreadyAtStop: isAtStop
                )
            }
        }
    }
    
    // MARK: - Journey Timing

    func manualRefreshTiming() async {
        guard let stopId = self.activeJourney?.currentStop?.mbtaStopId else { return }

        // Debounce: prevent spamming refresh
        let now = Date()
        if let last = self.lastManualRefresh, now.timeIntervalSince(last) < 2.0 {
            return
        }
        self.lastManualRefresh = now
        
        await self.validateJourneyCommand(.refreshTimes(stopId: stopId, isUserInitiated: true))
    }
    
    private func fetchJourneyTiming() async {
        guard
            let journey = self.activeJourney,
            let context = journey.timingContext
        else { return }
        let vehicleSearchStop = activeVehicleSearchStop(for: journey)
        let additionalPredictionStopIds = vehicleSearchStop.map {
            Set([$0.id])
        } ?? []
        do {
            let update = try await JourneyTimingEngine.shared.refreshJourneyTiming(
                route: journey.route,
                context: context,
                additionalPredictionStopIds: additionalPredictionStopIds
            )
            await validateJourneyCommand(.journeyTimingUpdate(update: update))
            await handleVehicleSearchResult(
                from: update,
                target: vehicleSearchStop,
                context: context
            )
        }
        catch {
            // A timing failure must not affect journey progression or tracking.
            print("JourneyEngine timing refresh failed: \(error)")
        }
    }

    // MARK: - Vehicle Search

    private func startVehicleSearch() {
        guard let journey = activeJourney,
              journey.trackedVehicleId == nil,
              journey.monitoringMode == .surface,
              journey.currentStop != nil else {
            isVehicleSearchActive = false
            return
        }
        isVehicleSearchActive = true
    }

    private func stopVehicleSearch() {
        isVehicleSearchActive = false
    }

    private func activeVehicleSearchStop(for journey: JourneyState) -> ResolvedStop? {
        guard isVehicleSearchActive else { return nil }
        guard journey.trackedVehicleId == nil,
              journey.monitoringMode == .surface,
              let currentStop = journey.currentStop else {
            stopVehicleSearch()
            return nil
        }
        return currentStop
    }

    private func handleVehicleSearchResult(from update: JourneyTimingUpdate, target: ResolvedStop?, context: JourneyTimingContext) async {
        guard isVehicleSearchActive,
              let target,
              let journey = activeJourney,
              journey.timingContext == context,
              journey.currentStop?.id == target.id,
              journey.trackedVehicleId == nil,
              journey.monitoringMode == .surface,
              let slice = update.predictionSlices.first(where: {
                  $0.predictedStopId == target.id
              }),
              let prediction = slice.livePredictions.first(where: {
                  $0.vehicleId != nil && $0.tripId != nil
              }),
              let vehicleId = prediction.vehicleId,
              let tripId = prediction.tripId else {
            return
        }

        await validateJourneyCommand(
            .vehicleSearchResult(vehicleId: vehicleId, tripId: tripId)
        )
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
    
    private func manageTimingRefreshTimer(for journey: JourneyState) {
        if journey.timingContext != nil {
            if timingRefreshTask == nil {
                startTimingRefreshTimer()
            }
        } else {
            stopTimingRefreshTimer()
        }
    }
    
    internal func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        var journeyToSave = journey
        //update JourneyState before saving
        journeyToSave.timeSaved = Date()
        
        //update Journey Engine observable state for ease of use
        self.activeJourney = journeyToSave
    
        userDefaultsClient.saveActiveJourney(journeyToSave)
        manageTimingRefreshTimer(for: journeyToSave)
        
        for continuation in journeyUpdateContinuations.values {
            continuation.yield(.activeJourneyChanged(journeyToSave))
        }
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        stopTimingRefreshTimer()
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
        print("JourneyEngine ending route")
        clearActiveJourneyAndPublish()
        stopTimingRefreshTimer()
        stopVehicleSearch()
        
        lastTimingRefreshTime = nil
        routeEndTimerTask?.cancel()
        routeEndTimerTask = nil
        
        motionListeningTask?.cancel()
        motionListeningTask = nil
        
        matchedPath = nil
        trackedVehicleId = nil
        trackedTripId = nil
        trackedBoardingStopId = nil
        
        await SurfaceManager.shared.killManager()
        await UndergroundManager.shared.killManager()
        await MotionManager.shared.stopCommands()
        await LiveActivityManager.shared.endActivity()
        await JourneyTimingEngine.shared.resetJourneyTiming()
    }
    
    // MARK: - Timers
    
    private func startTimingRefreshTimer() {
        stopTimingRefreshTimer()
        timingRefreshTask = Task {
            while !Task.isCancelled {
                let timeSinceLastFetch = lastTimingRefreshTime.map { Date().timeIntervalSince($0) } ?? 15.0
                let timeToWait = max(0, 15.0 - timeSinceLastFetch)
                
                try? await Task.sleep(nanoseconds: UInt64(timeToWait * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                if let journey = self.activeJourney, let stop = journey.currentStop {
                    await validateJourneyCommand(.refreshTimes(stopId: stop.mbtaStopId, isUserInitiated: false))
                }
            }
        }
    }
    
    private func stopTimingRefreshTimer() {
        timingRefreshTask?.cancel()
        timingRefreshTask = nil
    }
    
    ///Kills Journey in case user never leaves area
    private func startRouteEndTimer(seconds: Int) {
        routeEndTimerTask?.cancel()
        routeEndTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self.endRoute()
        }
    }
    
}

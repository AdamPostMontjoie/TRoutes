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
    case executeEntry(stopId:String)
    case executeExit(stopId:String)
    case approachingStop(stopId: String)
    case missedVehicle(stopId: String)
    case confirmDeparture(stopId: String)
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
    
    private var journeyUpdateContinuation: AsyncStream<JourneyUpdate>.Continuation?
    private var locationListeningTask: Task<Void, Never>?
    private var undergroundListeningTask: Task<Void, Never>?
    private var predictionRefreshTask: Task<Void, Never>?
    
    //underground fields
    private var matchedPath:MatchedLegPath?
    private var trackedVehicleId: String?
    private var trackedTripId: String?
    private var trackedBoardingStopId: String?
    
    // Surface Handoff Reconciliation
    struct RecentlyDepartedVehicle {
        let vehicleId: String
        let tripId: String
        let timestamp: Date
    }
    private var surfaceDepartureQueue: [RecentlyDepartedVehicle] = []
    
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
                startPredictionRefreshTimer()
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
        journeyUpdateContinuation?.yield(.journeyTerminated(.trackingReconciliationFailed))
        await endRoute()
    }
    
    // MARK: - Stream Listeners
    
    func startListeningToLocationEvents() async {
        guard locationListeningTask == nil else { return }
        let stream = await RegionManager.shared.makeEventStream()
        
        locationListeningTask = Task {
            for await event in stream {
                await self.journeyCommandValidator(event)
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
                await self.journeyCommandValidator(event)
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
    
    ///Streams active journey to UI
    func makeJourneyUpdateStream() async -> AsyncStream<JourneyUpdate> {
        let (stream, continuation) = AsyncStream<JourneyUpdate>.makeStream()
        self.journeyUpdateContinuation = continuation
        
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
                startPredictionRefreshTimer()
            } else {
                await startListeningToUndergroundEvents()
            }
            await monitorNextStop(stop: firstStop)
            await self.fetchPredictions(for: firstStop)
        }
    }
    
    // MARK: - Action Validation (Inputs)
    
    //this will handle both widget and in app i think
    func manualEventValidator(_ event:ManualEvent) async{
        guard let currentStop = userDefaultsClient.loadActiveJourney()?.currentStop else { return }
        switch event {
        case .atStopTapped:
            await self.journeyCommandValidator(JourneyCommand.executeEntry(stopId: currentStop.mbtaStopId))
        case .nextStopTapped:
            await self.journeyCommandValidator(JourneyCommand.executeExit(stopId: currentStop.mbtaStopId))
        }
    }
    
    //did we already receive this valid command from a different source and make the change?
    func journeyCommandValidator(_ event:JourneyCommand) async{
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else {return}
        switch event {
            case let .executeEntry(stopId:id):
                //ok, this is a new update
                if currentJourney.movementStatus == .enRoute && currentJourney.currentStop?.mbtaStopId == id {
                    print("JourneyEngine accepted entry \(id)")
                    await handleJourneyAction(.arriveAtStop)
                } else {
                    print("JourneyEngine ignored entry \(id) current: \(currentJourney.currentStop?.mbtaStopId ?? "nil") status: \(currentJourney.movementStatus)")
                }
            case let .executeExit(stopId:id):
            if currentJourney.movementStatus == .atStop && currentJourney.currentStop?.mbtaStopId == id {
                print("JourneyEngine accepted exit \(id)")
                
                //if we exit on surface, we grab the last known vehicle to have exited, or the currently tracked one if none exists
                //this is to handle overwriting the tracked vehicle with the predictions api before exit has been registered
                if currentJourney.monitoringMode == .surface {
                    surfaceDepartureQueue.removeAll { Date().timeIntervalSince($0.timestamp) > 45 }
                    //could be increased in reliability by making api call to check position
                    if let recent = surfaceDepartureQueue.last {
                        print("JourneyEngine: Surface geofence exit matched with recently departed vehicle \(recent.vehicleId). Reconciling.")
                        trackedVehicleId = recent.vehicleId
                        trackedTripId = recent.tripId
                        if let trip = trackedTripId {
                            await refreshTripTrackingData(tripId: trip)
                        }
                    } else {
                        print("JourneyEngine: Surface geofence exit with no recently departed vehicles in grace period. Keeping current tracked vehicle.")
                    }
                    surfaceDepartureQueue.removeAll()
                }
                
                await handleJourneyAction(.departFromStop)
            } else {
                print("JourneyEngine ignored exit \(id) current: \(currentJourney.currentStop?.mbtaStopId ?? "nil") status: \(currentJourney.movementStatus)")
            }
        case let .approachingStop(stopId: id):
            if currentJourney.movementStatus == .enRoute,
               currentJourney.currentStop?.mbtaStopId == id {
                let userMessage = "Approaching \(currentJourney.currentStop?.stopName ?? id)"
                await sendNotification(debug: "Approaching \(id)", user: userMessage)
            }
        case let .missedVehicle(stopId: id):
            print("JourneyEngine missedVehicle for \(id)")
            await handleMissedVehicle(stopId: id)
        case let .refreshTimes(stopId: id):
            if let currentStop = currentJourney.currentStop,
               currentStop.mbtaStopId == id {
                await handleJourneyAction(.evaluatePredictionRefresh)
            }
        case let .confirmDeparture(stopId: id):
            print("JourneyEngine confirmDeparture for \(id)")
            guard var journey = userDefaultsClient.loadActiveJourney(),
                  journey.currentStop?.mbtaStopId == id,
                  journey.movementStatus == .atStop else {
                break
            }
            journey.pendingDepartureConfirmation = true
            saveActiveJourneyAndPublish(journey)
            await handleJourneyAction(.departFromStop)
        case .locationAuthorizationDenied:
            journeyUpdateContinuation?.yield(.journeyTerminated(.locationAuthorizationDenied))
            await endRoute()
        
        case .monitoringFailed(stopId: let stopId, error: let error):
            print("monitoring failed for \(stopId): \(error)")
            //Possibly yield warning notification in UG mode as well, Transit does on their app
            //Perhaps if we become less reliant on api only in that mode
            let isSurface = currentJourney.monitoringMode == .surface
            let userMessage = (isSurface && error == .locationUnknown) ? "GPS signal lost or inaccurate. Tracking may be degraded." : nil
            await sendNotification(debug: "monitoring failed for \(stopId): \(error)", user: userMessage)
        }
    }
    
    func handleDepartureConfirmation(boarded: Bool) async {
        guard var journey = userDefaultsClient.loadActiveJourney() else { return }
        
        journey.pendingDepartureConfirmation = false
        saveActiveJourneyAndPublish(journey)
        
        if boarded {
            if journey.movementStatus == .atStop {
                await handleJourneyAction(.departFromStop)
            }
            return
        }
        
        trackedVehicleId = nil
        trackedTripId = nil
        matchedPath = nil
        surfaceDepartureQueue.removeAll()
        
        if journey.movementStatus == .atStop,
           let currentStop = journey.currentStop {
            await resetAfterMissedVehicle(at: currentStop)
        } else {
            await handleJourneyAction(.backtrackToStop)
        }
    }
    
    private func handleMissedVehicle(stopId: String) async {
        guard let journey = userDefaultsClient.loadActiveJourney() else { return }
        
        await sendNotification(debug: "Missed vehicle at \(stopId)", user: "Looks like you missed this train. Recalculating next departure...")
        
        trackedVehicleId = nil
        trackedTripId = nil
        matchedPath = nil
        surfaceDepartureQueue.removeAll()
        
        if journey.currentStop?.mbtaStopId == stopId,
           journey.movementStatus == .atStop,
           let currentStop = journey.currentStop {
            await resetAfterMissedVehicle(at: currentStop)
        } else if journey.movementStatus == .enRoute {
            await handleJourneyAction(.backtrackToStop)
        } else {
            print("JourneyEngine ignored missedVehicle \(stopId) current: \(journey.currentStop?.mbtaStopId ?? "nil") status: \(journey.movementStatus)")
        }
    }
    
    private func resetAfterMissedVehicle(at stop: ResolvedStop) async {
        guard var journey = userDefaultsClient.loadActiveJourney() else { return }
        
        journey.pendingDepartureConfirmation = false
        journey.movementStatus = .atStop
        journey.predictionState = .loading(stopId: stop.mbtaStopId)
        saveActiveJourneyAndPublish(journey)
        
        await monitorNextStop(stop: stop)
        await fetchPredictions(for: stop)
    }
    
    // MARK: - Journey Effects (Outputs)
    
    //ask for more time in background?
    private func handleJourneyAction(_ action: JourneyAction) async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let effects = action.reduce(state: &currentJourney)
        saveActiveJourneyAndPublish(currentJourney)
        await runJourneyEffects(effects)
    }

    private func runJourneyEffects(_ effects: [JourneyEffect]) async {
        for effect in effects {
            switch effect {
            case let .monitorStop(stop):
                print("JourneyEngine effect: registerRegion for \(stop.mbtaStopId)")
                //use shared version
                await monitorNextStop(stop: stop)
                
            case let .fetchPredictions(stop):
                print("JourneyEngine effect: fetchPredictions for \(stop.mbtaStopId)")
                await fetchPredictions(for: stop)
                
            case let .fetchTransferPredictions(stop):
                print("JourneyEngine effect: fetchTransferPredictions for \(stop.mbtaStopId)")
                await fetchTransferPredictions(for: stop)
                
            case let .sendNotification(debug, user):
                print("JourneyEngine effect: sendNotification - \(debug)")
                await sendNotification(debug: debug, user: user)
            case let .switchMonitoringMode(mode):
               await switchMonitoringMode(newMode:mode)
                
            case .endRoute:
                print("JourneyEngine effect: endRoute")
                await endRoute()
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
            startPredictionRefreshTimer()
        case .underground:
            //end RGM
            await RegionManager.shared.stopFunction()
            stopPredictionRefreshTimer()
            //start UGM
            print("underground monitoring")
            await startListeningToUndergroundEvents()
        }
        saveActiveJourneyAndPublish(currentJourney)
    }

    func monitorNextStop(stop:ResolvedStop) async {
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let mode = currentJourney.monitoringMode
        let isWaitingToBoard = stop.journeyRole != .final && stop.journeyRole != .intermediate
        print("JourneyEngine monitorNextStop stop: \(stop.mbtaStopId) mode: \(mode) role: \(stop.journeyRole)")
        switch mode {
        case .surface:
            print("surface monitoring")
            await RegionManager.shared.registerRegion(
                for: stop,
                previousMonitoringMode: currentJourney.previousStop?.monitoringMode
            )
            // Capture vehicle ID at boarding/transfer stops so it's available
            // if the mode switches to underground mid-leg.
            if isWaitingToBoard {
                _ = await prepareTrackedVehicleForUndergroundMonitoring(stop: stop, journey: currentJourney)
            }
        case .underground:
            print("underground monitoring")
            await UndergroundManager.shared.startSession()
            if await prepareTrackedVehicleForUndergroundMonitoring(stop: stop, journey: currentJourney),
               let trackedVehicleId,
               let trackedTripId {
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
                print("JourneyEngine underground tracking not ready for \(stop.mbtaStopId)")
            }
        }
        
    }
    
    // MARK: - MBTA API & Predictions
    
    func manualRefreshPredictions() async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney(),
              let currentStop = currentJourney.currentStop else { return }
        
        
        currentJourney.predictionState = .loading(stopId: currentStop.mbtaStopId)
        saveActiveJourneyAndPublish(currentJourney)
        await fetchPredictions(for: currentStop)
    }
    
    
    private func fetchPredictions(for stop: ResolvedStop) async {
        do {
            let predictionResponse = try await mbtaClient.fetchTransitTimes(stop)
            
            await savePredictionResult(for: stop, result: .success(predictionResponse))
        } catch {
            await savePredictionResult(for: stop, result: .failure(error))
        }
    }
    

    private func savePredictionResult(for stop: ResolvedStop, result: Result<[TransitPrediction], Error>) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard freshJourney.currentStop?.mbtaStopId == stop.mbtaStopId else {
            print("User manually advanced route during API call. Discarding stale times.")
            return
        }
        
        switch result {
        case let .success(predictionResults):
            let times = predictionResults.map(\.display)
            if times.isEmpty {
                freshJourney.predictionState = .unavailable(stopId: stop.mbtaStopId, message: "No predictions available")
            } else {
                freshJourney.predictionState = .loaded(stopId: stop.mbtaStopId, times:times)
                
                if freshJourney.monitoringMode == .surface,
                   freshJourney.movementStatus == .atStop,
                   freshJourney.currentStop?.journeyRole != .final,
                   freshJourney.currentStop?.journeyRole != .intermediate {
                    
                    if let currentVehicle = trackedVehicleId, let currentTrip = trackedTripId {
                        let isStillPredicted = predictionResults.contains { $0.vehicleId == currentVehicle && $0.tripId == currentTrip }
                        if !isStillPredicted {
                            print("JourneyEngine: Tracked vehicle \(currentVehicle) departed surface stop according to API. Entering grace period.")
                            surfaceDepartureQueue.append(
                                RecentlyDepartedVehicle(vehicleId: currentVehicle, tripId: currentTrip, timestamp: Date())
                            )
                            
                            if let nextPrediction = predictionResults.first(where: { $0.vehicleId != nil && $0.tripId != nil }),
                               let nextTrip = nextPrediction.tripId {
                                trackedVehicleId = nextPrediction.vehicleId
                                trackedTripId = nextTrip
                                print("JourneyEngine: Locked onto next vehicle \(nextPrediction.vehicleId ?? "") for surface tracking")
                            } else {
                                trackedVehicleId = nil
                                trackedTripId = nil
                            }
                        }
                    }
                    
                    surfaceDepartureQueue.removeAll { Date().timeIntervalSince($0.timestamp) > 45 }
                }
            }
        case .failure:
            freshJourney.predictionState = .unavailable(stopId: stop.mbtaStopId, message: "Cannot reach predictions")
        }
        
        saveActiveJourneyAndPublish(freshJourney)
    }
    
    private func fetchTransferPredictions(for stop: ResolvedStop) async {
        do {
            let predictionResponse = try await mbtaClient.fetchTransitTimes(stop)
            await saveTransferPredictionResult(for: stop, result: .success(predictionResponse))
        } catch {
            await saveTransferPredictionResult(for: stop, result: .failure(error))
        }
    }
    
    private func saveTransferPredictionResult(for stop: ResolvedStop, result: Result<[TransitPrediction], Error>) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        switch result {
        case let .success(predictionResults):
            let times = predictionResults.map(\.display)
            if times.isEmpty {
                freshJourney.transferPredictionState = .unavailable(stopId: stop.mbtaStopId, message: "No predictions available")
            } else {
                freshJourney.transferPredictionState = .loaded(stopId: stop.mbtaStopId, times: times)
            }
        case .failure:
            freshJourney.transferPredictionState = .unavailable(stopId: stop.mbtaStopId, message: "Cannot reach predictions")
        }
        
        saveActiveJourneyAndPublish(freshJourney)
    }
    
    private func fetchPredictionsAndSelectVehicle(stop:ResolvedStop) async -> TransitPrediction? {
        do {
            let predictionResponse = try await mbtaClient.fetchTransitTimes(stop)
            guard let selectedPrediction = predictionResponse.first(where: { $0.vehicleId != nil && $0.tripId != nil }),
                  let tripId = selectedPrediction.tripId else {
                print("JourneyEngine no selected prediction for \(stop.mbtaStopId)")
                return nil
            }
            print("JourneyEngine selected prediction stop: \(stop.mbtaStopId) vehicle: \(selectedPrediction.vehicleId ?? "nil") trip: \(tripId)")
            trackedVehicleId = selectedPrediction.vehicleId
            trackedTripId = tripId
            trackedBoardingStopId = stop.mbtaStopId
            await refreshTripTrackingData(tripId: tripId)
            return selectedPrediction
        } catch {
            print("error")
            return nil
        }
    }
    
    private func refreshTripTrackingData(tripId:String) async  {
        do {
            let tripTrackingData = try await mbtaClient.fetchTripTrackingData(tripId)
            // we need a new path once we get new trip data
            updateMatchedLegPath(tripTrackingData: tripTrackingData)
            
        } catch {
            handleVehicleFetchError(error: error)
            
        }
    }
    
    private func handleVehicleFetchError(error: Error){
        print("this is where we could deal with internet issues, like timeout errors or api issues")
    }
    
    private func updateMatchedLegPath(tripTrackingData:LiveTripTrackingData) {
        guard let currentLeg = userDefaultsClient.loadActiveJourney()?.currentLeg else {
            print("JourneyEngine no current leg for matched path")
            return
        }
        guard matchedPath?.matches(leg: currentLeg, tripId: tripTrackingData.tripId) != true else {
            print("JourneyEngine matched path already current")
            return
        }

        print("JourneyEngine update matched path trip: \(tripTrackingData.tripId) leg: \(currentLeg.legIndex) pattern: \(currentLeg.selectedPatternId)")
        matchedPath = MatchedLegPath(
            leg: currentLeg,
            tripTrackingData: tripTrackingData
        )
    }

    private func prepareTrackedVehicleForUndergroundMonitoring(stop: ResolvedStop, journey: JourneyState) async -> Bool {
        if matchedPathIsCurrent(for: journey),
           trackedVehicleId != nil,
           trackedTripId != nil {
            print("JourneyEngine reuse tracked vehicle for \(stop.mbtaStopId)")
            trackedBoardingStopId = stop.mbtaStopId
            return true
        }

        print("JourneyEngine fetch predictions to select vehicle for \(stop.mbtaStopId)")
        return await fetchPredictionsAndSelectVehicle(stop: stop) != nil
    }

    private func matchedPathIsCurrent(for journey: JourneyState) -> Bool {
        guard let currentLeg = journey.currentLeg,
              let trackedTripId else {
            return false
        }

        return matchedPath?.matches(leg: currentLeg, tripId: trackedTripId) == true
    }
    

    
    // MARK: - State Publishing Helpers
    
    private func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        var journeyToSave = journey
        journeyToSave.trackedVehicleId = self.trackedVehicleId
        journeyToSave.trackedTripId = self.trackedTripId
        journeyToSave.trackedBoardingStopId = self.trackedBoardingStopId
        journeyToSave.timeSaved = Date()
        
        userDefaultsClient.saveActiveJourney(journeyToSave)
        journeyUpdateContinuation?.yield(.activeJourneyChanged(journeyToSave))
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        journeyUpdateContinuation?.yield(.activeJourneyChanged(nil))
        journeyUpdateContinuation?.finish()
        journeyUpdateContinuation = nil
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
        surfaceDepartureQueue.removeAll()
        await RegionManager.shared.killManager()
        await UndergroundManager.shared.killManager()
    }
    
    // MARK: - Timers
    
    // MARK: - Prediction Refresh Timer (surface mode)
    
    private func startPredictionRefreshTimer() {
        stopPredictionRefreshTimer()
        predictionRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await handleJourneyAction(.evaluatePredictionRefresh)
            }
        }
    }
    
    private func stopPredictionRefreshTimer() {
        predictionRefreshTask?.cancel()
        predictionRefreshTask = nil
    }
    
}

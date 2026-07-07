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
    case refreshTimes(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}


///Manages The Journey
actor JourneyEngine {

    ///Singleton
    static let shared = JourneyEngine()
    
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.databaseClient) var databaseClient
    
    private var journeyUpdateContinuation: AsyncStream<JourneyUpdate>.Continuation?
    private var locationListeningTask: Task<Void, Never>?
    private var undergroundListeningTask: Task<Void, Never>?
    private var predictionRefreshTask: Task<Void, Never>?
    
    //underground fields
    private var matchedPath:MatchedLegPath?
    private var trackedVehicleId: String?
    private var trackedTripId: String?
    private var trackedBoardingStopId: String?
    
    func restoreActiveJourneyIfNeeded() async {
        guard let journey = userDefaultsClient.loadActiveJourney(),
              let currentStop = journey.currentStop
        else { return }

        await startListeningToLocationEvents()
        let context = determineTrackingContext(for: currentStop, in: journey)
        await RegionManager.shared.registerRegion(for: currentStop, context: context)
    }
    
    private func determineTrackingContext(for stop: ResolvedStop, in journey: JourneyState) -> RegionManager.TrackingContext {
        // If it's an intermediate stop, we are riding on the vehicle.
        if stop.journeyRole == .intermediate {
            return .ridingAlongSurface
        }
        
        // If it's the very first stop, we are walking to the station.
        if journey.stopIndex == 0 {
            return .arrivingOnFoot
        }
        
        // If it's a transfer stop or final stop, check the previous stop's mode
        let prevIndex = journey.stopIndex - 1
        if journey.stopOrder.indices.contains(prevIndex) {
            let prevStop = journey.stopOrder[prevIndex]
            if prevStop.monitoringMode == .underground {
                return .emergingFromUnderground
            } else {
                // If previous was surface, we might just be switching vehicles.
                // Or arriving at the final stop while riding on the surface.
                return stop.journeyRole == .final ? .ridingAlongSurface : .arrivingOnFoot
            }
        }
        
        return .arrivingOnFoot
    }
    
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
    
    //this is what is called to start fresh route
    //This needs to be modified once we start differentiating between streams. 
    func beginRoute(route:ResolvedUserRoute) async -> AsyncStream<JourneyUpdate> {
        let (stream, continuation) = AsyncStream<JourneyUpdate>.makeStream()
        self.journeyUpdateContinuation = continuation
        
        let journey = JourneyState(route: route)
        saveActiveJourneyAndPublish(journey)
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
        
        return stream
    }
    
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
                await handleJourneyAction(.departFromStop)
            } else {
                print("JourneyEngine ignored exit \(id) current: \(currentJourney.currentStop?.mbtaStopId ?? "nil") status: \(currentJourney.movementStatus)")
            }
        case let .approachingStop(stopId: id):
            if currentJourney.movementStatus == .enRoute,
               currentJourney.currentStop?.mbtaStopId == id {
                await sendNotification(message: "Approaching \(id)")
            }
        case let .missedVehicle(stopId: id):
            trackedVehicleId = nil
            trackedTripId = nil
            matchedPath = nil
            await handleJourneyAction(.backtrackToStop)
        case let .refreshTimes(stopId: id):
            if let currentStop = currentJourney.currentStop,
               currentStop.mbtaStopId == id {
                await handleJourneyAction(.evaluatePredictionRefresh)
            }
        case .authorizationDenied:
            print("the user deauthorized during journey")
            
        case .monitoringFailed(stopId: let stopId, error: let error):
            print("monitoring failed for \(stopId): \(error)")
        }
    }
    
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
                
            case let .sendNotification(message):
                print("JourneyEngine effect: sendNotification - \(message)")
                await sendNotification(message: message)
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
//    func monitorCurrentStop(stop:ResolvedStop) async {
//        
//    }
    func monitorNextStop(stop:ResolvedStop) async {
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let mode = currentJourney.monitoringMode
        let isWaitingToBoard = stop.journeyRole != .final && stop.journeyRole != .intermediate
        print("JourneyEngine monitorNextStop stop: \(stop.mbtaStopId) mode: \(mode) role: \(stop.journeyRole)")
        switch mode {
        case .surface:
            print("surface monitoring")
            let context = determineTrackingContext(for: stop, in: currentJourney)
            await RegionManager.shared.registerRegion(for: stop, context: context)
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
                //heavily gated later, just to test passing
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
            guard let selectedPrediction = predictionResponse.first,
                  let tripId = selectedPrediction.tripId,
                  selectedPrediction.vehicleId != nil else {
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
    

    
    private func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        userDefaultsClient.saveActiveJourney(journey)
        journeyUpdateContinuation?.yield(.activeJourneyChanged(journey))
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        journeyUpdateContinuation?.yield(.activeJourneyChanged(nil))
        journeyUpdateContinuation?.finish()
        journeyUpdateContinuation = nil
    }
    
    func sendNotification(message:String) async{
        await notificationsClient.debugStringNotification(message)
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
    func authorizationDenied(){
        
    }
    func monitoringFailed(){
        
    }
    
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

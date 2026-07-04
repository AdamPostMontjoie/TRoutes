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
    case refreshTimes(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}

enum MonitoringMode:Equatable, Codable {
    case underground
    case surface
}


///Manages Reacting to Journey Events
actor JourneyEngine {
    
    ///Singleton
    static let shared = JourneyEngine()
    
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.databaseClient) var databaseClient
    
    private var journeyUpdateContinuation: AsyncStream<JourneyUpdate>.Continuation?
    private let journeyUpdates: AsyncStream<JourneyUpdate>
    private var locationListeningTask: Task<Void, Never>?
    private var undergroundListeningTask: Task<Void, Never>?
    
    init(){
        var extractedContinuation: AsyncStream<JourneyUpdate>.Continuation?
        self.journeyUpdates = AsyncStream { continuation in
            extractedContinuation = continuation
            continuation.onTermination = { _ in
                
            }
        }
        self.journeyUpdateContinuation = extractedContinuation
    }
    
    func restoreActiveJourneyIfNeeded() async {
        guard let journey = userDefaultsClient.loadActiveJourney(),
              let currentStop = journey.currentStop
        else { return }

        await startListeningToLocationEvents()
        await RegionManager.shared.registerRegion(for: currentStop)
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
        let stream = await UndergroundManager.shared.makeEventStream()
        
        undergroundListeningTask = Task {
            for await event in stream {
                await self.journeyCommandValidator(event)
            }
            self.locationEventStreamDidFinish()
        }
    }
    
    private func locationEventStreamDidFinish() {
        locationListeningTask = nil
    }
    
    func requestAuthorization() async {
        await RegionManager.shared.requestAlwaysAuthorization()
    }
    
    //this is what is called to start fresh route
    //This needs to be modified once we start differentiating between streams. 
    func beginRoute(route:UserRoute) async -> AsyncStream<JourneyUpdate> {
        let journey = JourneyState(route: route)
        saveActiveJourneyAndPublish(journey)
        switch journey.monitoringMode {
        case .underground:
            await startListeningToUndergroundEvents()
        case .surface:
            await startListeningToLocationEvents()
        }
        
        if let firstStop = journey.currentStop {
            await RegionManager.shared.startMonitoring(firstStop: firstStop)
            await self.fetchPredictions(for: firstStop)
        }
        return journeyUpdates
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
                    await handleJourneyAction(.arriveAtStop)
                }
            case let .executeExit(stopId:id):
            if currentJourney.movementStatus == .atStop && currentJourney.currentStop?.mbtaStopId == id {
                await handleJourneyAction(.departFromStop)
            }
        case let .refreshTimes(stopId: id):
            if currentJourney.movementStatus == .atStop,
               let currentStop = currentJourney.currentStop,
               currentStop.mbtaStopId == id {
                await fetchPredictions(for: currentStop)
            }
        case .authorizationDenied:
            print("no user deauthorized during journey")
            
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
            case let .registerRegion(stop):
                print("JourneyEngine effect: registerRegion for \(stop.mbtaStopId)")
                await RegionManager.shared.registerRegion(for: stop)
                
            case let .fetchPredictions(stop):
                print("JourneyEngine effect: fetchPredictions for \(stop.mbtaStopId)")
                await fetchPredictions(for: stop)
                
            case let .sendNotification(message):
                print("JourneyEngine effect: sendNotification - \(message)")
                await sendNotificaition(message: message)
                
            case .endRoute:
                print("JourneyEngine effect: endRoute")
                await endRoute()
            }
        }
    }
    
    func manualRefreshPredictions() async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney(),
              let currentStop = currentJourney.currentStop else { return }
        
        
        currentJourney.predictionState = .loading(stopId: currentStop.mbtaStopId)
        saveActiveJourneyAndPublish(currentJourney)
        await journeyCommandValidator(.refreshTimes(stopId: currentStop.mbtaStopId))
    }
    
    
    private func fetchPredictions(for stop: Stop) async {
        do {
            let predictionResponse = try await mbtaClient.fetchTransitTimes(stop)
            
            await savePredictionResult(for: stop, result: .success(predictionResponse))
        } catch {
            await savePredictionResult(for: stop, result: .failure(error))
        }
    }
    

    private func savePredictionResult(for stop: Stop, result: Result<[TransitPrediction], Error>) async {
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        // Can check against more specific request id guard, but for now ensure new stop wasn't set by another journey command while we awaited change.
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
                if let firstPrediction = predictionResults.first,
                   firstPrediction.tripId != nil {
                    let resolvedRoute = await resolveRouteForUndergroundTracking(route: freshJourney.route)
                    let currentLeg = resolvedRoute?.legs.first { leg in
                        resolvedLeg(leg, startsAt: stop.mbtaStopId)
                    }

                    if let currentLeg {
                        await UndergroundManager.shared.setTrackedVehicle(
                            prediction: firstPrediction,
                            leg: currentLeg
                        )
                    }
                }
            }
        case .failure:
            freshJourney.predictionState = .unavailable(stopId: stop.mbtaStopId, message: "Cannot reach predictions")
        }
        
        saveActiveJourneyAndPublish(freshJourney)
    }

    // Temporary bridge until JourneyState owns resolved-route progress.
    private func resolveRouteForUndergroundTracking(route: UserRoute) async -> ResolvedUserRoute? {
        do {
            return try await databaseClient.resolveUserRoute(route)
        } catch {
            print("JourneyEngine temporary route resolution failed: \(error)")
            return nil
        }
    }

    private func resolvedLeg(_ leg: ResolvedLeg, startsAt stopId: String) -> Bool {
        leg.startStop.mbtaStopId == stopId ||
        leg.startStop.platformId == stopId ||
        leg.startStop.stationId == stopId
    }
    
    private func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        userDefaultsClient.saveActiveJourney(journey)
        journeyUpdateContinuation?.yield(.activeJourneyChanged(journey))
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        journeyUpdateContinuation?.yield(.activeJourneyChanged(nil))
        //terminate stream here too
    }
    
    func sendNotificaition(message:String) async{
        await notificationsClient.debugStringNotification(message)
    }
    
    func endRoute() async {
        clearActiveJourneyAndPublish()
        await RegionManager.shared.stopAll()
        await UndergroundManager.shared.stopSession()
    }
    func authorizationDenied(){
        
    }
    func monitoringFailed(){
        
    }

//    func locationEventValidator(_ event:LocationEvent) async {
//        let currentJourney = userDefaultsClient.loadActiveJourney()
//        await notificationsClient.debugStringNotification("JourneyEngine received \(event), currentStop: \(currentJourney?.currentStop?.mbtaStopId ?? "nil"), status: \(String(describing: currentJourney?.movementStatus))")
//        switch event {
//            case let .enteredStop(stopId:id):
//                //we're receiving entered data for the correct stop, and we're not yet counted as there
//                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .atStop {
//                    await self.journeyCommandValidator(JourneyCommand.executeEntry(stopId: id))
//                }
//            case let .exitedStop(stopId:id):
//                //we're receiving exited data for the correct stop, and we're currently counted as there
//                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .enRoute {
//                    await self.journeyCommandValidator(JourneyCommand.executeExit(stopId: id))
//                }
//                
//            default:
//                //handle monitoring and authorization error
//                print("uh")
//        }
//    }
    
}

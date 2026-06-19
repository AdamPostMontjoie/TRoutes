//
//  JourneyEngine.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/17/26.
//

import ComposableArchitecture
import CoreLocation


enum LocationEvent: Equatable {
    case enteredStop(stopId: String)
    case exitedStop(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}

//fill in later
enum MotionEvent: Equatable {
    
}

enum ManualEvent: Equatable {
    case nextStopTapped
    case atStopTapped
}

enum JourneyCommand: Equatable {
    case executeEntry(stopId:String)
    case executeExit(stopId:String)
}


///Manages Reacting to Journey Events
actor JourneyEngine {
    
    ///Singleton
    static let shared = JourneyEngine()
    
    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.mbtaClient) var mbtaClient
    
    private var journeyUpdateContinuation: AsyncStream<JourneyUpdate>.Continuation?
    private let journeyUpdates: AsyncStream<JourneyUpdate>
    private var isListeningToLocationEvents = false
    
    init(){
        var extractedContinuation: AsyncStream<JourneyUpdate>.Continuation?
        self.journeyUpdates = AsyncStream { continuation in
            extractedContinuation = continuation
            continuation.onTermination = { _ in
                print("journey update stream termination")
            }
        }
        self.journeyUpdateContinuation = extractedContinuation
    }
    
    func startListeningToLocationEvents() async{
        guard !isListeningToLocationEvents else { return }
        isListeningToLocationEvents = true
        defer { isListeningToLocationEvents = false }
        
        //listen to stream
        let stream = await RegionManager.shared.eventStream
        for await event in stream {
           await self.locationEventValidator(event)
        }
    }
    
    func requestAuthorization() async {
        await RegionManager.shared.requestAlwaysAuthorization()
    }
    
    //this is what is called to start fresh route
    //not always needed, as on background wakeup regions will already be monitored
    //initialize activeJourney
    func beginRoute(route:RouteStruct) async -> AsyncStream<JourneyUpdate> {
        let journey = JourneyState(route: route)
        saveActiveJourneyAndPublish(journey)
        
        if let firstStop = journey.currentStop {
            await RegionManager.shared.startMonitoring(firstStop: firstStop)
        }
        
        Task {
            await self.startListeningToLocationEvents()
        }
        
        return journeyUpdates
    }
    
    func locationEventValidator(_ event:LocationEvent) async {
        let currentJourney = userDefaultsClient.loadActiveJourney()
        switch event {
            case let .enteredStop(stopId:id):
                //we're receiving entered data for the correct stop, and we're not yet counted as there
                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .atStop {
                    await self.journeyCommandValidator(JourneyCommand.executeEntry(stopId: id))
                }
            case let .exitedStop(stopId:id):
                //we're receiving exited data for the correct stop, and we're currently counted as there
                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .enRoute {
                    await self.journeyCommandValidator(JourneyCommand.executeExit(stopId: id))
                }
                
            default:
                //handle monitoring and authorization error
                print("uh")
        }
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
        }
    }
    
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
                await RegionManager.shared.registerRegion(for: stop)
                
            case .fetchPredictions:
                await fetchPredictions()
                
            case let .sendNotification(message):
                await sendNotificaition(message: message)
                
            case .endRoute:
                await endRoute()
            }
        }
    }
    
    func fetchPredictions() async {
        guard let currentStop = userDefaultsClient.loadActiveJourney()?.currentStop else { return }
        var times: [String] = []
        do {
            times = try await mbtaClient.fetchTransitTimes(currentStop)
        } catch {
            //this will set the display for times unavaible, mbta down, etc depending on error
        }
        
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        //can check against more specific request id guard, but for now ensure new stop wasn't set by another journey command while we awaited change
        guard freshJourney.currentStop?.mbtaStopId == currentStop.mbtaStopId else {
            print("User manually advanced route during API call. Discarding stale times.")
            return
        }
        
        freshJourney.activePredictionTimes = times
        freshJourney.needTimes = false
        saveActiveJourneyAndPublish(freshJourney)
    }
    
    private func saveActiveJourneyAndPublish(_ journey: JourneyState) {
        userDefaultsClient.saveActiveJourney(journey)
        journeyUpdateContinuation?.yield(.activeJourneyChanged(journey))
    }
    
    private func clearActiveJourneyAndPublish() {
        userDefaultsClient.clearActiveJourney()
        journeyUpdateContinuation?.yield(.activeJourneyChanged(nil))
    }
    
    func sendNotificaition(message:String) async{
        await notificationsClient.debugStringNotification(message)
    }
    
    func endRoute() async {
        clearActiveJourneyAndPublish()
        await RegionManager.shared.stopAll()
    }
    func authorizationDenied(){
        
    }
    func monitoringFailed(){
        
    }
    
}


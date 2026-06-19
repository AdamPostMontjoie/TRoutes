//
//  JourneyEngine.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/17/26.
//

import ComposableArchitecture


enum LocationEvent: Equatable {
    case enteredStop(stopId: String)
    case exitedStop(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}

//fill in later
enum MotionEvent: Equatable {
    
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
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.mbtaClient) var mbtaClient
    
    init(){
        //perhaps instantly check what the userdefaults is
    }
    
    func startListeningToLocationEvents() async{
        //listen to stream
        let stream = await RegionManager.shared.eventStream
        for await event in stream {
           await self.locationEventValidator(event)
        }
    }
    
    func locationEventValidator(_ event:LocationEvent) async {
        let currentJourney = userDefaultsClient.loadActiveJourney()
        switch event {
            case let .enteredStop(stopId:id):
                //we're receiving entered data for the correct stop, and we're not yet counted as there
                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .atStop {
                    await self.journeyEventDeterminitor(JourneyCommand.executeEntry(stopId: id))
                }
            case let .exitedStop(stopId:id):
                //we're receiving exited data for the correct stop, and we're currently counted as there
                if currentJourney?.currentStop?.mbtaStopId == id && currentJourney?.movementStatus != .enRoute {
                    await self.journeyEventDeterminitor(JourneyCommand.executeExit(stopId: id))
                }
                
            default:
                //handle monitoring and authorization error
                print("uh")
        }
    }
    //did we already receive this valid command from a different source and make the change?
    
    func journeyEventDeterminitor(_ event:JourneyCommand) async{
        guard let currentJourney = userDefaultsClient.loadActiveJourney() else {return}
        switch event {
            case let .executeEntry(stopId:id):
                //ok, this is a new update
                if currentJourney.movementStatus == .enRoute && currentJourney.currentStop?.mbtaStopId == id {
                    await handle(.arriveAtStop)
                }
            case let .executeExit(stopId:id):
            if currentJourney.movementStatus == .atStop && currentJourney.currentStop?.mbtaStopId == id {
                await handle(.departFromStop)
            }
        }
    }
    
    private func handle(_ action: JourneyAction) async {
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        let effects = action.reduce(state: &currentJourney)
        userDefaultsClient.saveActiveJourney(currentJourney)
        await run(effects)
    }
    
    func enteredStop() async{
        await handle(.arriveAtStop)
    }
    
    func exitedStop() async{
        await handle(.departFromStop)
    }
    
    private func run(_ effects: [JourneyEffect]) async {
        for effect in effects {
            switch effect {
            case let .registerRegion(stop):
                await RegionManager.shared.registerRegion(for: stop)
                
            case let .fetchPredictions(stop):
                await fetchPredictions(for: stop)
                
            case let .sendNotification(message):
                await sendNotificaition(message: message)
                
            case .endRoute:
                endRoute()
            }
        }
    }
    
    private func fetchPredictions(for stop: Stop) async {
        var times: [String] = []
        do {
            times = try await mbtaClient.fetchTransitTimes(stop)
        } catch {
            //this will set the display for times unavaible, mbta down, etc depending on error
        }
        
        guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
        //can check against more specific request id guard
        guard freshJourney.currentStop?.mbtaStopId == stop.mbtaStopId else {
            print("User manually advanced route during API call. Discarding stale times.")
            return
        }
        
        freshJourney.activePredictionTimes = times
        freshJourney.needTimes = false
        userDefaultsClient.saveActiveJourney(freshJourney)
    }
    
    func sendNotificaition(message:String) async{
        await notificationsClient.debugStringNotification(message)
    }
    
    func endRoute(){
        
    }
    func authorizationDenied(){
        
    }
    func monitoringFailed(){
        
    }
    
}


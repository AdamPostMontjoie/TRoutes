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
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else {return}
        switch event {
            case let .executeEntry(stopId:id):
                //ok, this is a new update
                if currentJourney.movementStatus == .enRoute && currentJourney.currentStop?.mbtaStopId == id {
                    //set this to block any new mutuations
                    currentJourney.movementStatus = .atStop
                    userDefaultsClient.saveActiveJourney(currentJourney)
                    await self.enteredStop()
                }
            case let .executeExit(stopId:id):
            if currentJourney.movementStatus == .atStop && currentJourney.currentStop?.mbtaStopId == id {
                //set this to block any new mutuations
                currentJourney.movementStatus = .enRoute
                userDefaultsClient.saveActiveJourney(currentJourney)
                await self.exitedStop()
            }
        }
    }
    
    func enteredStop() async{
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard var currentStop = currentJourney.currentStop else {
            return
        }
        switch currentStop.stopType {
        case .transferStop:

            var times:[String] = []
            //we overlap, so we need to skip exit of the transfer stop
            if currentStop.overlapsWithNext {
                guard let newStop = currentJourney.advanceToNextStop() else {
                    return
                }
                currentJourney.needTimes = true
                currentJourney.activePredictionTimes = []
                currentStop = newStop
                userDefaultsClient.saveActiveJourney(currentJourney)
                await RegionManager.shared.registerRegion(for: newStop)
                do {
                    times = try await mbtaClient.fetchTransitTimes( newStop)
                } catch {
                    //this will set the display for times unavaible, mbta down, etc depending on error
                }
                guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
                guard freshJourney.currentStop?.mbtaStopId == currentStop.mbtaStopId else {
                        print("User manually advanced route during API call. Discarding stale times.")
                        return
                }
                currentJourney = freshJourney
            }
            currentJourney.activePredictionTimes = times
            currentJourney.needTimes = false
            userDefaultsClient.saveActiveJourney(currentJourney)
            
        case .boardingStop:
            currentJourney.needTimes = true
            userDefaultsClient.saveActiveJourney(currentJourney)
            var times:[String] = []
            do {
                times = try await mbtaClient.fetchTransitTimes(currentStop)
            } catch {
                //this will set the display for times unavaible, mbta down, etc depending on error
            }
            guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
            guard freshJourney.currentStop?.mbtaStopId == currentStop.mbtaStopId else {
                    print("User manually advanced route during API call. Discarding stale times.")
                    return
            }
            freshJourney.activePredictionTimes = times
            freshJourney.needTimes = false
            userDefaultsClient.saveActiveJourney(freshJourney)
            
        case .finalStop:
            //end of route
            return
        }
    }
    func exitedStop() async{
        guard var currentJourney = userDefaultsClient.loadActiveJourney() else { return }
        guard let currentStop = currentJourney.currentStop else {
            return
        }
        switch currentStop.stopType {
        case .transferStop:
            if !currentStop.overlapsWithNext{
               
                guard let newStop = currentJourney.advanceToNextStop() else {
                    return
                }
                currentJourney.activePredictionTimes = []
                currentJourney.needTimes = true
                userDefaultsClient.saveActiveJourney(currentJourney)
                await RegionManager.shared.registerRegion(for: newStop)
                var times:[String] = []
                do {
                    times = try await mbtaClient.fetchTransitTimes( newStop)
                } catch {
                    //this will set the display for times unavaible, mbta down, etc depending on error
                }
                guard var freshJourney = userDefaultsClient.loadActiveJourney() else { return }
                guard freshJourney.currentStop?.mbtaStopId == newStop.mbtaStopId else {
                        print("User manually advanced route during API call. Discarding stale times.")
                        return
                }
                freshJourney.activePredictionTimes = times
                freshJourney.needTimes = false
                userDefaultsClient.saveActiveJourney(freshJourney)
            }
        case .boardingStop:
            guard let newStop = currentJourney.advanceToNextStop() else {
                return
            }
            //we're on way to transfer or final stop, need no new times
            currentJourney.activePredictionTimes = []
            currentJourney.needTimes = false
            userDefaultsClient.saveActiveJourney(currentJourney)
            //register next
            await RegionManager.shared.registerRegion(for: newStop)

        case .finalStop:
            //kill route if they wander off
            self.endRoute()
        }
    }
    
    func endRoute(){
        
    }
    func authorizationDenied(){
        
    }
    func monitoringFailed(){
        
    }
    
}


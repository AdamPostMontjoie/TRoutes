//
//  RouteStarterFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation
import Dependencies

@Reducer
struct RouteStarterFeature {
    @ObservableState
    struct State: Equatable {
        var activeRouteDisplay: ActiveJourneyDisplayFeature.State {
            get {
                ActiveJourneyDisplayFeature.State(journey: activeJourney)
            }
            set {
                // Intentionally blank to satisfy WritableKeyPath requirement
                // without allowing child mutations.
            }
        }
        var createRoute = CreateRouteFeature.State()
        var routeSelector = SelectorFeature.State()
        var isCreateRoutePresented = false
        var isActiveJourneyPresented = false
        var activeJourney:JourneyState?
    }
    
    enum Action:Equatable {
        case activeRouteDisplay(ActiveJourneyDisplayFeature.Action)
        case createRoute(CreateRouteFeature.Action)
        case onCreateButtonTapped
        case onCreateRouteDismissed(Bool)
        case routeSelector(SelectorFeature.Action)
        
        case beginRoute(RouteStruct)
        case fetchPredictions(Stop)
        case endRoute
        
        // widget actions
        case refreshRoutes
        case forcedArrival //at stop button, bypasses region did enter
        case forcedDeparture // next stop button, bypasses region did exit
        
        
        case locationUpdateReceived(LocationEvent)
        case mbtaApiResponseReceived([String])
        
        //handlers for the possible location events
        //we may want to take in stop id and compare to avoid any cases with erroneously saved stuff
        case enteredStop
        case exitedStop
        case authorizationDenied
        case locationError
        
        
        case apiFailed
        
    }
    
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.liveActivityClient) var liveActivityClient
    @Dependency(\.mbtaClient) var mbtaClient
    var body: some ReducerOf<Self> {
        Scope(state: \.activeRouteDisplay, action: \.activeRouteDisplay) {
            ActiveJourneyDisplayFeature()
        }
        Scope(state: \.createRoute, action: \.createRoute) {
            CreateRouteFeature()
        }
        Scope(state: \.routeSelector, action: \.routeSelector) {
            SelectorFeature()
        }
        Reduce { state, action in
            switch action {
            
            case .onCreateButtonTapped:
                print("tapped")
                state.isCreateRoutePresented = true
                return .none
            case .createRoute(.delegate(.routeSaved)):
                return .send(.onCreateRouteDismissed(true))
            case .createRoute(.delegate(.dismiss)):
                return .send(.onCreateRouteDismissed(false))
            case let .onCreateRouteDismissed(refresh):
                state.isCreateRoutePresented = false
                state.createRoute = CreateRouteFeature.State()
                if refresh {
                    return .send(.routeSelector(.fetchRoutesFromDisk))
                } else {
                    return .none
                }
            //this starts the route from inside the app, most of the logic is kicked off here
            case let .routeSelector(.delegate(.startRoute(id))):
                
                //feels like a useless guard
                guard let selectedRoute = state.routeSelector.userRoutes.first(where: { $0.id == id}) else {
                    return .none
                }
                
                return .send(.beginRoute(selectedRoute))
                
                
            // starts the route
            case let .beginRoute(route):
                state.isActiveJourneyPresented = true
                state.activeJourney = JourneyState(route: route)
                state.activeRouteDisplay.journey = state.activeJourney
                
                guard let firstStop = route.legs.first?.startStop else {
                    return .none
                }
                return .run { send in
                    await send(.fetchPredictions(firstStop))
                    
                    let stream = try await locationClient.startMonitoring(firstStop)
                    
                    // Listen to the GPS (Wait at the pipe)
                    // This loop runs infinitely in the background until the effect is cancelled
                    for await location in stream{
                        await send(.locationUpdateReceived(location))
                    }
                }
            //this will be called on natural end or forceful cancelation
            case .endRoute:
                state.isActiveJourneyPresented = false
                state.activeJourney = nil
                return .run { send in
                    try await locationClient.stopMonitoring()
                }
            case let .fetchPredictions(stop):
                //we should probably clear all predictions instead of fetching new if en route to certain stops
                return .run { send in
                    do {
                        let times = try await mbtaClient.fetchTransitTimes(stop)
                        // Send the data back into the reducer
                        print(times)
                        await send(.mbtaApiResponseReceived(times))
                    }
                    catch {
                        await send(.apiFailed)
                    }
                }
            case let .mbtaApiResponseReceived(upcomingTimes):
               
                state.activeJourney?.activePredictionTimes = upcomingTimes
                state.activeRouteDisplay.journey = state.activeJourney
                return .none
            case .refreshRoutes:
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                return .send(.fetchPredictions(currentStop))
            //these will tell the location client it's time to force switch regions or whatever
            //location client will then send locationEvent into stream
            case .forcedArrival:
                return .none
            case .forcedDeparture:
                return .none
            //determine what the location event actually was
            //send the action that corresponds to that update.
            //those actions will update the state to correspond
            case let .locationUpdateReceived(locationEvent):
                switch locationEvent {
                case .enteredStop:
                    return .send(.enteredStop)
                case .exitedStop:
                    return .send(.exitedStop)
                case .authorizationDenied:
                    return .send(.authorizationDenied)
                case .monitoringFailed:
                    return .send(.locationError)
                }
            //handles what to do with state when user arrives at stop
            case .enteredStop:
                //ignore if already at stop
                guard state.activeJourney?.movementStatus == .enRoute else { return .none }
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                switch currentStop.stopType {
                case .transferStop:
                    //run effect
                    state.activeJourney?.stopIndex += 1
                    guard let newStop = state.activeJourney?.currentStop else {
                        return .none
                    }
                    //if they overlap, we're already at the next stop. if not, user is en route to the next stop
                    if currentStop.overlapsWithNext {
                        state.activeJourney?.movementStatus = .atStop
                    } else {
                        state.activeJourney?.movementStatus = .enRoute
                    }
                    return .run { send in
                        try await locationClient.registerNextStopRegion(newStop)
                        //get times for the new stop
                        await send(.fetchPredictions(newStop))
                    }
                    //fire did exit as either way, we're dropping bounds
                case .boardingStop:
                    //get new times, don't update current stop
                    state.activeJourney?.movementStatus = .atStop
                    return .send(.fetchPredictions(currentStop))
                    
                case .finalStop:
                    //user can dismiss via widget or leaving
                    state.activeJourney?.movementStatus = .atStop
                    return .none
                }
            case .exitedStop:
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                switch currentStop.stopType {
                case .transferStop:
                    //this probably shouldn't happen? we should have already dropped monitoring here
                    return .none
                case .boardingStop:
                    //get new times, don't update current stop
                    state.activeJourney?.movementStatus = .enRoute
                    state.activeJourney?.stopIndex += 1
                    guard let newStop = state.activeJourney?.currentStop else {
                        return .none
                    }
                    return .run { send in
                        try await locationClient.registerNextStopRegion(newStop)
                        //we probably don't need predictions, because next stop with be transfer or final
                      //  await send(.fetchPredictions(newStop))
                    }
                case .finalStop:
                    //kill route if they wander off
                    return .send(.endRoute)
                }
            //kill the route, tell the user to navigate to settings
            case .authorizationDenied:
                return .run { send in
                    await send(.endRoute)
                    // send alert that tells the user they have to go to settings
                    // this should also display if they try and hit start while it's disabled every time
                    print("User must enable location services in settings")
                    // add a link/way for the user to navigate to settings page
                }
            case .locationError:
                return .none
            //also can trigger from widget?? figure out how later
            case .activeRouteDisplay(.delegate(.cancelRoute)):
                // Kill the tracking session
                state.activeJourney = nil
                state.activeRouteDisplay.journey = nil
                state.isActiveJourneyPresented = false
                
                return .run { _ in
                    await liveActivityClient.endActivity()
                    // Location client stream will automatically cancel when the effect ends
                }
            case .apiFailed:
                print("error goes here")
                return .none
            //does nothing
            case .activeRouteDisplay, .createRoute, .routeSelector:
                return .none
            
            }
        }
    }
}

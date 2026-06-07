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
        var activeRouteDisplay = ActiveJourneyDisplayFeature.State()
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
        case mbtaApiResponseReceived([String])
        
        case refreshRoutes
        //remove?
        case locationUpdateReceived(LocationData)
        
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
                
            case .refreshRoutes:
                return .none
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
                    // Fire the API call for the first stop
                    do {
                        let times = try await mbtaClient.fetchTransitTimes(firstStop)
                        // Send the data back into the reducer
                        await send(.mbtaApiResponseReceived(times))
            
                    } catch {
                        await send(.apiFailed)
                    }
                    
                    // Start the GPS (Turn on the faucet)
                    try? await locationClient.startMonitoring(firstStop)
                    
                    // Listen to the GPS (Wait at the pipe)
                    // This loop runs infinitely in the background until the effect is cancelled
                    for await location in await locationClient.locationStream() {
                        await send(.locationUpdateReceived(location))
                    }
                }
            case let .mbtaApiResponseReceived(upcomingTimes):
                // 1. Mutate the state safely
                state.activeJourney?.currentLeg.currentStop.nextTimes = upcomingTimes
                state.activeRouteDisplay.journey = state.activeJourney
                
                // 2. Now that the state has real times, launch the Lock Screen widget!
                if let activeJourney = state.activeJourney {
                    return .run { _ in
                        await liveActivityClient.startActivity(activeJourney.route)
                    }
                }
                return .none
                
                
            //this will update both the app state and the live activity when something changes
            //this comes from core location, so boundary has been triggered
            case let .locationUpdateReceived(newLocation):
                //we need to determine where we are and what that means for the JourneyState
                
                //if on stop, left stop, need to set to next stop, we update state.activeJourney based on that
                
                //most of the time, we will need to call the mbtaclient to get the next times for whatever we need
                
                //also update the widget
                if let activeJourney = state.activeJourney {
                    return .run { _ in
                        await liveActivityClient.updateActivity(activeJourney)
                    }
                }
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
            case .activeRouteDisplay:
                return .none
            case .createRoute:
                return .none
            case .routeSelector:
                return .none
            
            }
        }
    }
}

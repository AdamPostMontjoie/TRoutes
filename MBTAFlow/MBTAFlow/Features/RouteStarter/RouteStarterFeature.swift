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
        var activeRouteDisplay = ActiveRouteDisplayFeature.State()
        var createRoute = CreateRouteFeature.State()
        var routeSelector = SelectorFeature.State()
        var isCreateRoutePresented = false
        var isActiveRoutePresented = false
        var activeRoute:RouteState?
    }
    
    enum Action:Equatable {
        case activeRouteDisplay(ActiveRouteDisplayFeature.Action)
        case createRoute(CreateRouteFeature.Action)
        case onCreateButtonTapped
        case onCreateRouteDismissed
        case routeSelector(SelectorFeature.Action)
        
        case beginRoute(RouteStruct)
        case mbtaApiResponseReceived([String])
        
        //remove?
        case locationUpdateReceived(LocationData)
        
        case apiFailed
        
    }
    
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.liveActivityClient) var liveActivityClient
    @Dependency(\.mbtaClient) var mbtaClient
    var body: some ReducerOf<Self> {
        Scope(state: \.activeRouteDisplay, action: \.activeRouteDisplay) {
            ActiveRouteDisplayFeature()
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
                state.isCreateRoutePresented = false
                return .none
            case .onCreateRouteDismissed:
                //this handles the x out
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
                state.isActiveRoutePresented = true
                state.activeRoute = RouteState(route:route)
                
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
                state.activeRoute?.currentLeg.currentStop.nextTimes = upcomingTimes
                
                // 2. Now that the state has real times, launch the Lock Screen widget!
                if let activeRoute = state.activeRoute {
                    return .run { _ in
                        await liveActivityClient.startActivity(activeRoute.route)
                    }
                }
                return .none
                
                
            //this will update both the app state and the live activity when something changes
            //this comes from core location, so boundary has been triggered
            case let .locationUpdateReceived(newLocation):
                //we need to determine where we are and what that means for the routestate
                
                //if on stop, left stop, need to set to next stop, we update state.activeRoute based on that
                
                //most of the time, we will need to call the mbtaclient to get the next times for whatever we need
                
                //also update the widget
                if let activeRoute = state.activeRoute {
                    return .run { _ in
                        await liveActivityClient.updateActivity(activeRoute)
                    }
                }
                return .none
                    
            //also can trigger from widget?? figure out how later
            case .activeRouteDisplay(.delegate(.cancelRoute)):
                // Kill the tracking session
                state.activeRoute = nil
                state.isActiveRoutePresented = false
                
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

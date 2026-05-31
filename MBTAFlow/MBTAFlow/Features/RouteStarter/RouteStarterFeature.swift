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
        
        case locationUpdateReceived(LocationData)
        
    }
    
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.liveActivityClient) var liveActivityClient
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
                state.isCreateRoutePresented = true
                return .none
            case .onCreateRouteDismissed:
                state.isCreateRoutePresented = false
                return .none
            //this starts the route from inside the app, most of the logic is kicked off here
            case let .routeSelector(.delegate(.startRoute(routeId))):
                state.isActiveRoutePresented = true
                guard let selectedRoute = state.routeSelector.userRoutes.first(where: { $0.routeId == routeId }) else {
                    return .none
                }
                state.activeRoute = RouteState(route:selectedRoute)
                return .run { send in
                    // Start the Live Activity widget
                    await liveActivityClient.startActivity(selectedRoute)
                    
                    // Listen to the GPS stream
                    for await location in await locationClient.locationStream() {
                        await send(.locationUpdateReceived(location))
                    }
                }
            //this will update both the app state and the live activity when something changes
            case let .locationUpdateReceived(newLocation):
                // 1. Update your logic
                // e.g., state.activeRoute.checkIfArrived(at: newLocation)
                
                // 2. Push the new state to the widget
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

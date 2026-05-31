//
//  RouteStarterFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

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
        
    }
    
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
                return .none
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

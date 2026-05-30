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
        var activeRoute = ActiveRouteFeature.State()
        var createRoute = CreateRouteFeature.State()
        var routeSelector = SelectorFeature.State()
        var isCreateRoutePresented = false
        var isActiveRoutePresented = false
    }
    
    enum Action:Equatable {
        case activeRoute(ActiveRouteFeature.Action)
        case createRoute(CreateRouteFeature.Action)
        case onCreateButtonTapped
        case onCreateRouteDismissed
        case onDeleteButtonTapped(UUID)
        case routeSelector(SelectorFeature.Action)
        
    }
    
    var body: some ReducerOf<Self> {
        Scope(state: \.activeRoute, action: \.activeRoute) {
            ActiveRouteFeature()
        }
        Scope(state: \.createRoute, action: \.createRoute) {
            CreateRouteFeature()
        }
        Scope(state: \.routeSelector, action: \.routeSelector) {
            SelectorFeature()
        }
        Reduce { state, action in
            switch action {
            case .activeRoute:
                return .none
            case .createRoute:
                return .none
            case .onCreateButtonTapped:
                state.isCreateRoutePresented = true
                return .none
            case .onCreateRouteDismissed:
                state.isCreateRoutePresented = false
                return .none
            case .onDeleteButtonTapped(_):
                return .none
            case .routeSelector:
                return .none
            }
        }
    }
}

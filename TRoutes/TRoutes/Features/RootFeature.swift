//
//  RootFeature.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

@Reducer
struct RootFeature {
    @ObservableState
    struct State: Equatable {
        var application = ApplicationState()
        var routeStarter = RouteStarterFeature.State()
        var singleStop = SingleStopFeature.State()
        var selectedTab: Tab = .routeStarter
    }
    
    enum Tab { case routeStarter, singleStop }
    
    enum Action {
        case routeStarterTab(RouteStarterFeature.Action)
        case singleStopTab(SingleStopFeature.Action)
        case selectedTab(Tab)
    }
    
    var body: some ReducerOf<Self> {
        Scope(state: \.routeStarter, action: \.routeStarterTab) {
            RouteStarterFeature()
        }
        Scope(state: \.singleStop, action: \.singleStopTab) {
            SingleStopFeature()
        }
        Reduce { state, action in
            switch action {
            case let .selectedTab(tab):
                state.selectedTab = tab
                return .none
            case .routeStarterTab:
                return .none
            case .singleStopTab:
                return .none
            }
        }
    }
}

//
//  RootView.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import SwiftUI
import ComposableArchitecture

struct RootView: View {
    @Bindable var store: StoreOf<RootFeature>
    
    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.selectedTab)) {
            RouteStarterView(
                store: store.scope(state: \.routeStarter, action: \.routeStarterTab)
            )
            .tabItem {
                Label("Routes", systemImage: "map")
            }
            .tag(RootFeature.Tab.routeStarter)
            .task {
                store.send(.routeStarterTab(.startListeningToJourneyUpdates))
            }
            
            SingleStopView(
                store: store.scope(state: \.singleStop, action: \.singleStopTab)
            )
            .tabItem {
                Label("Single Stop", systemImage: "bus")
            }
            .tag(RootFeature.Tab.singleStop)
        }
    }
}

//
//  RootView.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import SwiftUI
import ComposableArchitecture

struct RootView: View {
    let store: StoreOf<RootFeature>
    
    var body: some View {
        RouteStarterView(
            store: store.scope(state: \.starter, action: \.starterTab)
        )
        .task {
            store.send(.starterTab(.startListeningToJourneyUpdates))
        }
    }
}

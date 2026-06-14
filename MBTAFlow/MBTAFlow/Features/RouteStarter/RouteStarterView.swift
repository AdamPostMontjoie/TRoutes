//
//  RouteStarterView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import SwiftUI
import ComposableArchitecture

struct RouteStarterView: View {
    @Bindable var store: StoreOf<RouteStarterFeature>

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The Banner now sits structurally above the list on the Y-axis
                if store.isActiveJourneyPresented {
                    ActiveJourneyDisplayView(
                        store: store.scope(
                            state: \.activeJourneyDisplay,
                            action: \.activeJourneyDisplay
                        )
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 4) // Adds breathing room between banner and list
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // The List takes up the remaining vertical space
                SelectorView(
                    store: store.scope(
                        state: \.routeSelector,
                        action: \.routeSelector
                    )
                )
            }
            .navigationTitle("Routes")
            .toolbar(store.isActiveJourneyPresented ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.onCreateButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            // Applying the animation to the VStack ensures the list is smoothly pushed down
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.isActiveJourneyPresented)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.isCreateRoutePresented },
                set: { isPresented in
                    if !isPresented {
                        store.send(.onCreateRouteDismissed(false))
                    }
                }
            )
        ) {
            CreateRouteView(
                store: store.scope(
                    state: \.createRoute,
                    action: \.createRoute
                )
            )
            .interactiveDismissDisabled(true)
        }
    }
}

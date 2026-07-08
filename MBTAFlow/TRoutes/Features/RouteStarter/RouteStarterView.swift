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
        NavigationStack(
            path: $store.scope(
                state: \.routeSelector.path,
                action: \.routeSelector.path
            )
        ) {
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
                ) {
                    if store.isDebugActive {
                        DebugDashboardView(
                            store: store.scope(
                                state: \.debugDashboardDisplay,
                                action: \.debugDashboardDisplay
                            )
                        )
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .sheet(
                    item: $store.scope(
                        state: \.destination?.userSettings,
                        action: \.destination.userSettings
                    )
                ) { userSettingsStore in
                    UserSettingsView(store: userSettingsStore)
                }
            }
            .navigationTitle("Routes")
            .toolbar(store.isActiveJourneyPresented ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.send(.onSettingsButtonTapped)
                    } label : {
                        Image(systemName: "gear")
                    }
                }
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
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.isDebugActive)
            .sheet(
                item: $store.scope(
                    state: \.destination?.locationAlert,
                    action: \.destination.locationAlert
                )
            ) { locationAlertStore in
                LocationAlertView(store: locationAlertStore)
                    // Prevents the user from swiping the sheet away without making a choice
                    .interactiveDismissDisabled()
            }
        } destination: { store in
            RouteReviewView(store: store)
        }
        .fullScreenCover(
            item: $store.scope(
                state: \.destination?.createRoute,
                action: \.destination.createRoute
            )
        ) { createRouteStore in
            CreateRouteView(store: createRouteStore)
                .interactiveDismissDisabled(true)
        }
        .alert(
            $store.scope(
                state: \.destination?.alert,
                action: \.destination.alert
            )
        )
        .sheet(
            item: $store.scope(
                state: \.destination?.welcome,
                action: \.destination.welcome
            )
        ) { welcomeStore in
            WelcomeView(store: welcomeStore)
                .interactiveDismissDisabled()
        }
        .task {
            store.send(.checkOnboarding)
        }
    }
}

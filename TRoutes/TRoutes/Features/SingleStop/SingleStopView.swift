//
//  SingleStopView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import SwiftUI
import ComposableArchitecture


struct SingleStopView: View {
    @Bindable var store: StoreOf<SingleStopFeature>
    
    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Stops")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            store.send(.onSettingsButtonTapped)
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
                .sheet(
                    item: $store.scope(
                        state: \.destination?.apiKeyAlert,
                        action: \.destination.apiKeyAlert
                    )
                ) { apiKeyAlertStore in
                    ApiKeyAlertView(store: apiKeyAlertStore)
                }
                .sheet(
                    item: $store.scope(
                        state: \.destination?.userSettings,
                        action: \.destination.userSettings
                    )
                ) { userSettingsStore in
                    UserSettingsView(store: userSettingsStore)
                }
                .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))

        } destination: { store in
            SearchedStationView(store: store)
        }
        .task {
            store.send(.onAppear)
        }
        .overlay(alignment: .bottom) {
            if store.isLiveActivityConfirmationPresented {
                Label("Launched Live Activity", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: store.isLiveActivityConfirmationPresented)
    }
    
    @ViewBuilder
    private var mainContent: some View {
        VStack {
            if store.hasValidApiKey {
                Group {
                    if store.search.query.isEmpty {
                        if store.locationPermissionDenied {
                            Spacer()
                            VStack(spacing: 12) {
                                Text("Location needed to find nearby stops")
                                    .foregroundColor(.secondary)
                                Button("Enable Location") {
                                    store.send(.requestLocationTapped)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Spacer()
                        } else {
                            StopsListView(store: store.scope(state: \.stopsList, action: \.stopsList))
                        }
                    } else {
                        StopSearchView(store: store.scope(state: \.search, action: \.search))
                    }
                }
                .searchable(
                    text: searchQueryBinding,
                    prompt: "Search stations"
                )
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Text("Set Up Stops Tab")
                        .font(.headline)
                    Text(FeatureFlags.stopPinningEnabled
                        ? "Add a free MBTA API key to view live arrivals for nearby, saved, and pinned stops."
                        : "Add a free MBTA API key to view live arrivals for nearby and saved stops.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add API Key") {
                        store.send(.apiKeyLinkTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                Spacer()
            }
        }
    }
    
    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { store.search.query },
            set: { store.send(.search(.queryChanged($0))) }
        )
    }
}

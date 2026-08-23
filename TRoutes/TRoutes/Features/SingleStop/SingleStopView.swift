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
                .navigationTitle("Single Stop")
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

        } destination: { store in
            SearchedStationView(store: store)
        }
        .task {
            store.send(.onAppear)
        }
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
                Button {
                    store.send(.apiKeyLinkTapped)
                } label: {
                    Text("Add an API Key to get started")
                }
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

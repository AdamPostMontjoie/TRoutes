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
        NavigationStack {
            VStack {
                if store.hasValidApiKey {
                    StopsListView(store: store.scope(state: \.stopsList, action: \.stopsList))
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
        }
    }
}

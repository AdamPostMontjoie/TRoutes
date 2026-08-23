//
//  ApiKeyAlertView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import SwiftUI
import ComposableArchitecture

struct ApiKeyAlertView: View {
    let store: StoreOf<ApiKeyAlertFeature>
    
    var body: some View {
        VStack(spacing: 24) {
            Image("APIKeyAlertImage")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .accessibilityHidden(true)

            Text("MBTA API Key Required")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            
            Text("The Stops tab checks arrivals for many stops and requires the MBTA's higher request limit.")
                .multilineTextAlignment(.center)
            
            Text("The Routes tab still works without a key. You can create a key for free from the link in Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Not Now", role: .cancel) {
                    store.send(.dismissButtonTapped)
                }
                .buttonStyle(.bordered)

                Button("Open Settings") {
                    store.send(.openSettingsButtonTapped)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

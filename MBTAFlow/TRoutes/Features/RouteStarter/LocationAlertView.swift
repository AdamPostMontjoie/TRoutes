//
//  LocationAlertView.swift
//  TRoutes
//
//  Created by Adam Post on 6/14/26.
//

import SwiftUI
import ComposableArchitecture

struct LocationAlertView: View {
    let store: StoreOf<LocationAlertFeature>
    
    var body: some View {
        VStack(spacing: 24) {
            switch store.mode {
            case .firstTime:
                Text("Location Services Required")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("We need location permissions to track your journey and provide live updates.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Continue") {
                    store.send(.continueButtonTapped)
                }
                .buttonStyle(.borderedProminent)
            case .changeSettings:
                Text("Location Services Are Disabled")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("Please enable location access in Settings to use navigation and track your route.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    Button("Cancel", role: .cancel) {
                        store.send(.cancelButtonTapped)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Settings") {
                        store.send(.settingsButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .routeInterrupted:
                Text("Location Services Were Interrupted")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("You disabled location access while a route was active. The route has been ended. Please enable location access in Settings to use navigation.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    Button("Cancel", role: .cancel) {
                        store.send(.cancelButtonTapped)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Settings") {
                        store.send(.settingsButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            }

        }
        .padding()
    }
}

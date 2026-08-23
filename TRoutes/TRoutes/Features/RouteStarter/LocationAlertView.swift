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
            Image("LocationAlertImage")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .accessibilityHidden(true)

            switch store.mode {
            case .firstTime:
                Text("Allow Location Access")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("T Routes uses your location to find nearby stops and provide live progress during active journeys.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Continue") {
                    store.send(.continueButtonTapped)
                }
                .buttonStyle(.borderedProminent)
            case .changeSettings:
                Text("Location Services Are Disabled")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("Enable location access in Settings to find nearby stops and use journey tracking.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    Button("Cancel", role: .cancel) {
                        store.send(.cancelButtonTapped)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Open Settings") {
                        store.send(.settingsButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .routeInterrupted:
                Text("Location Services Were Interrupted")
                    .font(.title2.bold())
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
                    
                    Button("Open Settings") {
                        store.send(.settingsButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            }

        }
        .padding()
    }
}

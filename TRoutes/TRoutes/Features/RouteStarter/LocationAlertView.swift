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
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Image("LocationAlertImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.5)
                    .accessibilityHidden(true)

                VStack(spacing: 24) {
                    modalContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private var modalContent: some View {
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
}

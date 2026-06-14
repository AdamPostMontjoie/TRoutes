//
//  LocationAlertView.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/14/26.
//

import SwiftUI
import ComposableArchitecture

struct LocationAlertView: View {
    let store: StoreOf<LocationAlertFeature>
    
    var body: some View {
        VStack(spacing: 24) {
            if store.mode == .firstTime {
                Text("We need location permissions")
                    .multilineTextAlignment(.center)
                
                Button("Continue") {
                    store.send(.continueButtonTapped)
                }
                .buttonStyle(.borderedProminent)
                
            } else {
                Text("Go to settings to enable location permissions")
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

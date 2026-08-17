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
            Text("API Key Required")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("To monitor individual stops in real time, you need a free MBTA API key. Tap the \(Image(systemName: "gear")) icon in the top left of the Routes tab to open Settings and add your key.")
            
            Text("You can create a free developer account and get a key in seconds from the MBTA website. A link is provided in Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Got It") {
                store.send(.dismissButtonTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

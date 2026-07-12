import ComposableArchitecture
import SwiftUI

struct WelcomeView: View {
    let store: StoreOf<WelcomeFeature>
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Placeholder for logo
            Image(systemName: "tram.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)
            
            Text("Welcome to T Routes!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            if store.isDebugActive {
                debugContentView
            } else {
                userContentView
            }
            
            Spacer()
            
            Button {
                store.send(.continueButtonClicked)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding()
    }
    
    @ViewBuilder
    private var userContentView: some View {
        VStack(spacing: 24) {
            featureRow(
                icon: "map.fill",
                title: "Plan Your Commute",
                description: "Create and save custom routes along the T to easily track your daily journey."
            )
            
            featureRow(
                icon: "bell.badge.fill",
                title: "Stay Informed",
                description: "Please enable notifications on the next screen to get real-time updates and alerts for your saved routes."
            )
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private var debugContentView: some View {
        VStack(spacing: 24) {
            featureRow(
                icon: "map.fill",
                title: "Plan Your Commute",
                description: "Create and save custom routes along the T to easily track your daily journey."
            )
            
            featureRow(
                icon: "bell.badge.fill",
                title: "Stay Informed",
                description: "Please enable notifications on the next screen to get real-time updates and alerts for your saved routes."
            )
            
            featureRow(
                icon: "ladybug.fill",
                title: "Tester Mode Active",
                description: "As a tester, you have a debug dashboard and debug notifications, which you can disable in settings for a standard user experience.",
                iconColor: .purple
            )
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private func featureRow(icon: String, title: String, description: String, iconColor: Color = .accentColor) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

//
//  ActiveJourneyDisplayView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct ActiveJourneyDisplayView: View {
    let store: StoreOf<ActiveJourneyDisplayFeature>
    
    var body: some View {
        HStack(spacing: 12) {
            // Live Activity style icon/indicator
            Image(systemName: "tram.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.blue) // Will map to your AccentColor later
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(store.journey?.route.name ?? "Active Route")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                // Placeholder for actual live data later
                Text("Fetching next stop...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Cancel button to end the journey and kill the location stream
            Button {
                store.send(.delegate(.cancelRoute))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
    }
}

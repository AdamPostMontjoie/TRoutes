//
//  StopRowView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import SwiftUI
import ComposableArchitecture

struct StopRowView: View {
    @Bindable var store: StoreOf<StopRowFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(store.stop.stopName)
                    .font(.body)
                
                Spacer()
                
                HStack(spacing: 8) { // Adds clean spacing between the two icons
                    // Edit Button
                    Button {
                        store.send(.editStopButtonTapped)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.title3) // Slightly larger icon
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(AnimatedIconButtonStyle())
                    
                    // Delete Button
                    Button {
                        store.send(.deleteStopButtonTapped)
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(AnimatedIconButtonStyle())
                }
            }
            
            Text("Lat: \(store.stop.latitude), Lon: \(store.stop.longitude)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// 1. Define the custom style
struct AnimatedIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 2. Padding INSIDE the label expands the invisible clickable area
            .padding(10)
            // 3. Defines the clickable shape so tapping near the icon works
            .contentShape(Circle())
            // 4. Subtle gray highlight behind the icon when actively pressed
            .background(
                Circle()
                    .fill(Color.gray.opacity(configuration.isPressed ? 0.15 : 0.0))
            )
            // 5. Shrinks the button by 10% when pressed for that "bouncy" feel
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            // 6. Applies a smooth, snappy physics animation to the scale and background changes
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

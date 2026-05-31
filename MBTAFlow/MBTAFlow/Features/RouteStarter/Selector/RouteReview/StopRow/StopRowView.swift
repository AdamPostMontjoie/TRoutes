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
            
                HStack(spacing: 0) { // Set spacing to 0 because the padding adds the space natively
                    // Edit Button
                    Button {
                        store.send(.editStopButtonTapped)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .padding(10) // Expands the hit target
                            .contentShape(Rectangle()) // Makes the transparent padding clickable
                    }
                    .buttonStyle(.borderless) // The SwiftUI standard for in-list buttons
                    
                    // Delete Button
                    Button {
                        store.send(.deleteStopButtonTapped)
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Text(store.stop.address)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

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
            Image(systemName: movementIconName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(movementIconColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(store.journey?.currentStop.stopName ?? "Active Journey")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                predictionTimesView
            }
            
            Spacer()
            
            Button {
                store.send(.cancelButtonTapped)
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
    
    private var movementIconName: String {
        switch store.journey?.movementStatus {
        case .atStop:
            return "mappin.circle.fill"
        case .enRoute, .none:
            return "arrow.right.circle.fill"
        }
    }
    
    private var movementIconColor: Color {
        switch store.journey?.movementStatus {
        case .atStop:
            return .red
        case .enRoute, .none:
            return .blue
        }
    }
    
    @ViewBuilder
    private var predictionTimesView: some View {
        if let predictionTimes = store.journey?.activePredictionTimes, !predictionTimes.isEmpty {
            Text(predictionTimes.joined(separator: "  •  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading predictions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

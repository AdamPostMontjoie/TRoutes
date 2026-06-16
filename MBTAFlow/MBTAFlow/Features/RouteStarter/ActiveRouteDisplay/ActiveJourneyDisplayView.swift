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
    @State private var refreshRotation = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stopDisplayText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    predictionTimesView
                }
                
                Spacer()
                
                cancelButton
            }
            
            HStack(spacing: 10) {
                if store.journey?.needTimes == true {
                    refreshButton
                }
                
                if store.shouldShowStopActionButton {
                    stopActionButton
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
    }
    
    private var refreshButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) {
                refreshRotation += 360
            }
            store.send(.refreshButtonTapped)
        } label: {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(refreshRotation))
                .frame(width: 40, height: 40)
                .background(.green)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh predictions")
    }
    
    private var stopActionButton: some View {
        Button {
            switch store.journey?.movementStatus {
            case .enRoute:
                store.send(.atStopButtonTapped)
            case .atStop:
                store.send(.nextStopButtonTapped)
            case .none:
                break
            }
        } label: {
            Image(systemName: store.movementIconName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(movementIconColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stopActionAccessibilityLabel)
    }
    
    private var cancelButton: some View {
        Button {
            store.send(.cancelButtonTapped)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel route")
    }
    
    private var movementIconColor: Color {
        switch store.journey?.movementStatus {
        case .enRoute, .none:
            return .red     // manual "I'm at the stop"
        case .atStop:
            return .blue    // manual "go to next stop"
        }
    }
    
    private var stopActionAccessibilityLabel: String {
        switch store.journey?.movementStatus {
        case .enRoute, .none:
            return "Mark as at stop"
        case .atStop:
            return "Go to next stop"
        }
    }
    
    private var stopDisplayText: String {
            guard let journey = store.journey, let stopName = journey.currentStop?.stopName else {
                return ""
            }
            
            switch journey.movementStatus {
            case .atStop:
                return "At: \(stopName)"
            case .enRoute:
                return "En route to: \(stopName)"
            }
        }
    
    @ViewBuilder
    private var predictionTimesView: some View {
        if let predictionTimes = store.journey?.activePredictionTimes, !predictionTimes.isEmpty {
            Text(predictionTimes.joined(separator: "  •  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if store.journey?.needTimes != false {
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

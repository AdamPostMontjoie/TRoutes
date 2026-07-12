//
//  ActiveJourneyDisplayView.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct ActiveJourneyDisplayView: View {
    let store: StoreOf<ActiveJourneyDisplayFeature>
    @State private var refreshRotation = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Top Level: Route & Destination
                HStack(alignment: .center, spacing: 8) {
                    if !store.shortRouteName.isEmpty {
                        Text(store.shortRouteName)
                            .font(.caption.bold())
                            .foregroundStyle(transitForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(transitColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if !store.routeDestination.isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                            .opacity(0.8)
                        Text(store.routeDestination)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    cancelButton
                }
                
                // Mid Level: Context
                ViewThatFits(in: .horizontal) {
                    // Fits horizontally
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        currentLocationBadge
                        if let destination = store.destinationContext {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                    }
                    
                    // Doesn't fit, fallback to stack
                    VStack(alignment: .leading, spacing: 8) {
                        currentLocationBadge
                        if let destination = store.destinationContext {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                        }
                    }
                }
                .padding(.top, 4)
                
                // Bottom Level: Focus Data (ETAs + Train Logo)
                if let activePrediction = store.journey?.activeLegPrediction {
                    predictionTimesBlock(
                        state: activePrediction.loadingState,
                        predictions: activePrediction.lastObservedPredictions,
                        color: transitColor,
                        iconName: store.currentTransitType?.iconName,
                        foregroundColor: transitForegroundColor
                    )
                    .padding(.top, 4)
                }
                
                if store.journey?.pendingDepartureConfirmation == true {
                    departureConfirmationPrompt
                }
                
                if store.shouldShowRefreshButton || store.shouldShowStopActionButton {
                    HStack(spacing: 16) {
                        if store.shouldShowRefreshButton {
                            refreshButton
                        }
                        
                        if store.shouldShowStopActionButton {
                            stopActionButton
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            
            // Transfer Banner (Bottom Bleed)
            let hasTransferContext = store.transferContext != nil
            let hasTransferPrediction = store.journey?.transferLegPrediction?.loadingState != nil
            
            if hasTransferContext || hasTransferPrediction {
                let transferColor = nextLegColor ?? transitColor
                let transferForeground = transferColor.isLightBackground ? Color.black : Color.white
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.headline)
                        
                        if let transferText = store.transferContext {
                            Text(transferText)
                                .font(.subheadline.bold())
                        } else if let journey = store.journey,
                                  let nextLeg = journey.legOrder.dropFirst(journey.legIndex + 1).first {
                            Text("Upcoming Transfer: \(nextLeg.transitType.rawValue)")
                                .font(.subheadline.bold())
                        }
                        
                        Spacer()
                    }
                    
                    if let transferPrediction = store.journey?.transferLegPrediction {
                        predictionTimesBlock(
                            state: transferPrediction.loadingState,
                            predictions: transferPrediction.lastObservedPredictions,
                            color: .white.opacity(0.2), // Frosted/muted background for the boxes so they don't clash with the solid colored banner
                            iconName: nextLegIconName,
                            foregroundColor: transferForeground
                        )
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(transferForeground)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(transferColor.gradient)
            }
        }
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
    }
    
    private var transitColor: Color {
        store.currentTransitType?.color ?? Color.accentColor
    }
    
    private var transitForegroundColor: Color {
        transitColor.isLightBackground ? .black : .white
    }
    
    private var nextLegColor: Color? {
        guard let journey = store.journey else { return nil }
        let nextIndex = journey.legIndex + 1
        guard nextIndex < journey.legOrder.count else { return nil }
        return journey.legOrder[nextIndex].transitType.color
    }
    
    private var nextLegIconName: String? {
        guard let journey = store.journey else { return nil }
        let nextIndex = journey.legIndex + 1
        guard nextIndex < journey.legOrder.count else { return nil }
        return journey.legOrder[nextIndex].transitType.iconName
    }
    
    private var currentLocationBadge: some View {
        Text(store.currentLocationContext)
            .font(.subheadline)
            .fontWeight(.bold)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .padding(.horizontal, -10)
                    .padding(.vertical, -6)
            }
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
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(refreshRotation))
                .frame(width: 40, height: 40)
                .background(.secondary.opacity(0.15))
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
                .background(transitColor.gradient)
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
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel Journey")
    }
    

    private var departureConfirmationPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Did you catch the train?")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            HStack(spacing: 8) {
                Button {
                    store.send(.confirmedBoardedTapped)
                } label: {
                    Label("Yes", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    store.send(.confirmedMissedTapped)
                } label: {
                    Label("No, Missed it", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var stopActionAccessibilityLabel: String {
        switch store.journey?.movementStatus {
        case .enRoute, .none:
            return "Mark as at stop"
        case .atStop:
            return "Go to next stop"
        }
    }
    

    
    @ViewBuilder
    private func timesRow(times: [String], predictions: [TransitPrediction] = [], color: Color, foregroundColor: Color, opacity: Double = 1.0) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                let prediction = predictions.indices.contains(index) ? predictions[index] : nil
                let bgStyle: AnyShapeStyle = (color == .white.opacity(0.2)) ? AnyShapeStyle(color) : AnyShapeStyle(color.gradient)
                let branchLabel = prediction?.branchLabel
                
                HStack(spacing: 4) {
                    if let branchLabel {
                        Text(branchLabel)
                            .font(.footnote.weight(.black))
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    
                    if time.lowercased().contains("stopped") {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Stopped")
                    } else {
                        Text(time)
                    }
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 60, maxHeight: 34)
                .padding(.horizontal, 10)
                .background(bgStyle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: color == .white.opacity(0.2) ? .clear : color.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private func predictionTimesBlock(state: PredictionLoadingState?, predictions: [TransitPrediction], color: Color, iconName: String?, foregroundColor: Color) -> some View {
        if let state = state {
            HStack(spacing: 8) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(transitColor)
                }
                
                switch state {
                case let .loaded(_, times):
                    timesRow(times: times, predictions: predictions, color: color, foregroundColor: foregroundColor)
                case .loading:
                    if predictions.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(color == .white.opacity(0.2) ? foregroundColor : color)
                            Text("Loading predictions")
                                .font(.headline)
                                .foregroundStyle(foregroundColor)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(color == .white.opacity(0.2) ? foregroundColor : color)
                            
                            timesRow(times: predictions.map(\.display), predictions: predictions, color: color, foregroundColor: foregroundColor, opacity: 0.5)
                        }
                    }
                case let .unavailable(_, message):
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .blendMode(.difference) 
                        .lineLimit(1)
                }
            }
        } else {
            EmptyView()
        }
    }
}

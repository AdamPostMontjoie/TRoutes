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
                    if !store.presentation.shortRouteName.isEmpty {
                        Text(store.presentation.shortRouteName)
                            .font(.caption.bold())
                            .foregroundStyle(transitForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(transitColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if !store.presentation.routeDestination.isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                            .opacity(0.8)
                        Text(store.presentation.routeDestination)
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
                        if let destination = store.presentation.destinationContext {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                    }
                    
                    // Doesn't fit, fallback to stack
                    VStack(alignment: .leading, spacing: 8) {
                        currentLocationBadge
                        if let destination = store.presentation.destinationContext  {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                        }
                    }
                }
                .padding(.top, 4)
                
                // Bottom Level: Focus Data (ETAs + Train Logo)
                if let state = store.presentation.activePredictionLoadingState {
                    predictionTimesBlock(
                        state: state,
                        times: store.presentation.activePredictions,
                        color: transitColor,
                        iconName: store.presentation.currentTransitType?.iconName,
                        iconColor: transitColor,
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
            let hasTransferContext = store.presentation.transferContext != nil
            let hasTransferPrediction = store.presentation.transferPredictionLoadingState != nil
            
            if hasTransferContext || hasTransferPrediction {
                let transferColor = store.presentation.nextLegTransitType?.color ?? transitColor
                let transferForeground = transferColor.isLightBackground ? Color.black : Color.white
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.headline)
                        
                        if let transferText = store.presentation.transferContext {
                            Text(transferText)
                                .font(.subheadline.bold())
                        } else if let nextLegType = store.presentation.nextLegTransitType {
                            Text("Upcoming Transfer: \(nextLegType.rawValue)")
                                .font(.subheadline.bold())
                        }
                        
                        Spacer()
                    }
                    
                    if let state = store.presentation.transferPredictionLoadingState {
                        predictionTimesBlock(
                            state: state,
                            times: store.presentation.transferPredictions ?? [],
                            color: .white.opacity(0.2), // Frosted/muted background for the boxes so they don't clash with the solid colored banner
                            iconName: store.presentation.nextLegTransitType?.iconName,
                            iconColor: transferForeground,
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
        store.presentation.currentTransitType?.color ?? Color.accentColor
    }
    
    private var transitForegroundColor: Color {
        transitColor.isLightBackground ? .black : .white
    }
    
    private var currentLocationBadge: some View {
        Text(store.presentation.currentLocationContext)
            .font(.subheadline)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
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
            HStack(spacing: 6) {
                Image(systemName: store.movementIconName)
                    .font(.title3)
                Text(stopActionText)
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(transitColor.gradient)
            .clipShape(Capsule())
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
    
    private var stopActionText: String {
        switch store.journey?.movementStatus {
        case .enRoute, .none:
            return "I'm Here"
        case .atStop:
            return "Next Stop"
        }
    }
    
    @ViewBuilder
    private func timesRow(times: [JourneyAttributes.PredictionDisplay], color: Color, foregroundColor: Color, opacity: Double = 1.0) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, prediction in
                let bgStyle: AnyShapeStyle = (color == .white.opacity(0.2)) ? AnyShapeStyle(color) : AnyShapeStyle(color.gradient)
                let branchLabel = prediction.badge
                
                HStack(spacing: 4) {
                    if let branchLabel {
                        Text(branchLabel)
                            .font(.footnote.weight(.black))
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    
                    if prediction.time.lowercased().contains("stopped") {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Stopped")
                    } else {
                        Text(prediction.time)
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
    private func predictionTimesBlock(state: PredictionLoadingState?, times: [JourneyAttributes.PredictionDisplay], color: Color, iconName: String?, iconColor: Color, foregroundColor: Color) -> some View {
        if let state = state {
            HStack(spacing: 8) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                }
                
                switch state {
                case .loaded:
                    timesRow(times: times, color: color, foregroundColor: foregroundColor)
                case .loading:
                    if times.isEmpty {
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
                            
                            timesRow(times: times, color: color, foregroundColor: foregroundColor, opacity: 0.5)
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

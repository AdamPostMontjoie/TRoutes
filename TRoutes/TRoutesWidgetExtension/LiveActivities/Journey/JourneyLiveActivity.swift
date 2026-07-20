//
//  JourneyLiveActivity.swift
//  TRoutes
//
//  Created by Adam Post on 7/17/26.
//

import WidgetKit
import ActivityKit
import SwiftUI

private func formatIslandTime(_ time: String) -> String {
    let lower = time.lowercased()
    if lower == "arriving" {
        return "ARR"
    } else if lower == "boarding" {
        return "BRD"
    }
    return time.replacingOccurrences(of: " min", with: "m")
}

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyAttributes.self) { context in
            // Lock screen/banner UI goes here
            JourneyLockScreenOrWatchView(state: context.state)
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.
                DynamicIslandExpandedRegion(.center) {
                    JourneyExpandedIslandView(state: context.state)
                }
            } compactLeading: {
                Text(context.state.shortRouteName)
                    .foregroundStyle(Color(hex: context.state.currentTransitColor))
                    .bold()
            } compactTrailing: {
                if let next = context.state.activePredictions.first {
                    Text(formatIslandTime(next.time))
                }
            } minimal: {
                if let next = context.state.activePredictions.first {
                    Text(formatIslandTime(next.time))
                        .foregroundStyle(Color(hex: context.state.currentTransitColor))
                        .bold()
                } else {
                    Text(context.state.shortRouteName)
                        .foregroundStyle(Color(hex: context.state.currentTransitColor))
                        .bold()
                }
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

struct JourneyLockScreenOrWatchView: View {
    @Environment(\.activityFamily) var activityFamily
    let state: JourneyAttributes.ContentState
    
    var body: some View {
        if activityFamily == .small {
            JourneyWatchOSView(state: state)
        } else {
            JourneyLockScreenView(state: state)
        }
    }
}

struct JourneyWatchOSView: View {
    let state: JourneyAttributes.ContentState
    
    private var watchDestinationText: String? {
        guard let dest = state.destinationContext else { return nil }
        let lower = dest.lowercased()
        if lower.contains("next stop") || lower.contains("last stop") {
            return "Next Stop"
        }
        if let firstWord = dest.components(separatedBy: " ").first, let count = Int(firstWord) {
            return count == 1 ? "Next Stop" : "\(count) Stops Left"
        }
        return dest
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Badge
            Text(state.shortRouteName)
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: state.currentTransitForegroundColor))
                .frame(minWidth: 36, minHeight: 32)
                .padding(.horizontal, 6)
                .background(Color(hex: state.currentTransitColor).gradient.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            Spacer(minLength: 0)
            
            // Content
            if let transferTimes = state.transferPredictions, !transferTimes.isEmpty {
                timesView(times: transferTimes, colorHex: state.nextLegColor ?? state.currentTransitColor, foregroundHex: state.nextLegForegroundColor ?? state.currentTransitForegroundColor)
            } else if !state.activePredictions.isEmpty {
                timesView(times: state.activePredictions, colorHex: state.currentTransitColor, foregroundHex: state.currentTransitForegroundColor)
            } else if let dest = watchDestinationText {
                Text(dest)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(state.currentLocationContext)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func timesView(times: [JourneyAttributes.PredictionDisplay], colorHex: String, foregroundHex: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(times.prefix(2).enumerated()), id: \.offset) { index, prediction in
                HStack(spacing: 2) {
                    if let badge = prediction.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 14, height: 14)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    Text(formatIslandTime(prediction.time))
                        .font(.subheadline.bold())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color(hex: foregroundHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(hex: colorHex).gradient.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .layoutPriority(1)
            }
        }
    }
}

struct JourneyExpandedIslandView: View {
    let state: JourneyAttributes.ContentState
    
    private var transitColor: Color {
        Color(hex: state.currentTransitColor)
    }
    
    private var transitForegroundColor: Color {
        Color(hex: state.currentTransitForegroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Level: Route & Context combined, equal fonts
            HStack(alignment: .center, spacing: 8) {
                if !state.shortRouteName.isEmpty {
                    Text(state.shortRouteName)
                        .font(.subheadline.bold())
                        .foregroundStyle(transitForegroundColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(transitColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                Text(state.currentLocationContext)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            
            // Bottom Level: Focus Data (ETAs + Train Logo)
            if let loadingState = state.activePredictionLoadingState {
                predictionTimesBlock(
                    state: loadingState,
                    times: state.activePredictions,
                    color: transitColor,
                    iconName: state.currentIconName,
                    iconColor: transitColor,
                    foregroundColor: transitForegroundColor
                )
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func timesRow(times: [JourneyAttributes.PredictionDisplay], color: Color, foregroundColor: Color, opacity: Double = 1.0) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, prediction in
                let bgStyle: AnyShapeStyle = (color == .white.opacity(0.2)) ? AnyShapeStyle(color) : AnyShapeStyle(color.gradient)
                
                HStack(spacing: 4) {
                    if let badge = prediction.badge {
                        Text(badge)
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
                        Text(formatIslandTime(prediction.time))
                    }
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 60, minHeight: 34)
                .padding(.horizontal, 10)
                .background(bgStyle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: color == .white.opacity(0.2) ? .clear : color.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private func predictionTimesBlock(state: JourneyAttributes.WidgetPredictionLoadingState, times: [JourneyAttributes.PredictionDisplay], color: Color, iconName: String?, iconColor: Color, foregroundColor: Color) -> some View {
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
            case let .unavailable(message):
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .blendMode(.difference) 
                    .lineLimit(1)
            }
        }
    }
}

struct JourneyLockScreenView: View {
    let state: JourneyAttributes.ContentState
    
    private var transitColor: Color {
        Color(hex: state.currentTransitColor)
    }
    
    private var transitForegroundColor: Color {
        Color(hex: state.currentTransitForegroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // Top Level: Route & Destination
                HStack(alignment: .center, spacing: 8) {
                    if !state.shortRouteName.isEmpty {
                        Text(state.shortRouteName)
                            .font(.caption.bold())
                            .foregroundStyle(transitForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(transitColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if !state.routeDestination.isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                            .opacity(0.8)
                        Text(state.routeDestination)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                }
                
                // Mid Level: Context
                ViewThatFits(in: .horizontal) {
                    // Fits horizontally
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        currentLocationBadge
                        if let destination = state.destinationContext {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                    }
                    
                    // Doesn't fit, fallback to stack
                    VStack(alignment: .leading, spacing: 8) {
                        currentLocationBadge
                        if let destination = state.destinationContext {
                            Text(destination)
                                .font(.footnote)
                                .opacity(0.7)
                        }
                    }
                }
                .padding(.top, 2)
                
                // Bottom Level: Focus Data (ETAs + Train Logo)
                if let loadingState = state.activePredictionLoadingState {
                    predictionTimesBlock(
                        state: loadingState,
                        times: state.activePredictions,
                        color: transitColor,
                        iconName: state.currentIconName,
                        iconColor: transitColor,
                        foregroundColor: transitForegroundColor
                    )
                    .padding(.top, 2)
                }
            }
            .padding(16)
            
            // Transfer Banner (Bottom Bleed)
            let hasTransferContext = state.transferContext != nil
            let hasTransferPrediction = state.transferPredictionLoadingState != nil
            
            if hasTransferContext || hasTransferPrediction {
                let transferColor = state.nextLegColor != nil ? Color(hex: state.nextLegColor!) : transitColor
                let transferForeground = state.nextLegForegroundColor != nil ? Color(hex: state.nextLegForegroundColor!) : Color.white
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.headline)
                        
                        if let transferText = state.transferContext {
                            Text(transferText)
                                .font(.subheadline.bold())
                        } else if let nextLegType = state.nextLegIconName {
                            Text("Upcoming Transfer")
                                .font(.subheadline.bold())
                        }
                        
                        Spacer()
                    }
                    
                    if let loadingState = state.transferPredictionLoadingState {
                        predictionTimesBlock(
                            state: loadingState,
                            times: state.transferPredictions ?? [],
                            color: .white.opacity(0.2), // Frosted/muted background for the boxes so they don't clash with the solid colored banner
                            iconName: state.nextLegIconName,
                            iconColor: transferForeground,
                            foregroundColor: transferForeground
                        )
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(transferForeground)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(transferColor.gradient)
            }
        }
        .foregroundStyle(.primary)
        // I will keep the custom container layout exactly as it is in the banner view, 
        // without padding, because we set .activityBackgroundTint(Color.clear) in the configuration
        // so this view effectively BECOMES the banner.
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
    
    private var currentLocationBadge: some View {
        Text(state.currentLocationContext)
            .font(.subheadline)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
            }
    }
    
    @ViewBuilder
    private func timesRow(times: [JourneyAttributes.PredictionDisplay], color: Color, foregroundColor: Color, opacity: Double = 1.0) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, prediction in
                let bgStyle: AnyShapeStyle = (color == .white.opacity(0.2)) ? AnyShapeStyle(color) : AnyShapeStyle(color.gradient)
                
                HStack(spacing: 4) {
                    if let badge = prediction.badge {
                        Text(badge)
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
                        Text(formatIslandTime(prediction.time))
                    }
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 60, minHeight: 34)
                .padding(.horizontal, 10)
                .background(bgStyle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: color == .white.opacity(0.2) ? .clear : color.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private func predictionTimesBlock(state: JourneyAttributes.WidgetPredictionLoadingState, times: [JourneyAttributes.PredictionDisplay], color: Color, iconName: String?, iconColor: Color, foregroundColor: Color) -> some View {
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
            case let .unavailable(message):
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .blendMode(.difference) 
                    .lineLimit(1)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

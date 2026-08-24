//
//  StopBannerView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//
import SwiftUI
import ComposableArchitecture

struct StopBannerView: View {
    @Bindable var store: StoreOf<StopBannerFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(store.routePresentation.badgeText)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(store.transitForegroundColor)
                    .frame(minWidth: 28, minHeight: 24)
                    .padding(.horizontal, 6)
                    .background(store.transitColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.target.stopName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if let routeName = store.routePresentation.detailText {
                        Text(routeName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                
                if store.target.isDirectionLocked {
                    HStack(spacing: 12) {
                        liveActivityButton

                        if FeatureFlags.stopPinningEnabled {
                            Button {
                                store.send(.pinTapped, animation: .default)
                            } label: {
                                Image(systemName: "pin.fill")
                                    .font(.title3)
                                    .foregroundStyle(store.transitColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 12) {
                        liveActivityButton

                        if FeatureFlags.stopPinningEnabled {
                            Button {
                                store.send(.pinTapped, animation: .default)
                            } label: {
                                Image(systemName: store.pinnedDirections.contains(store.activeDirectionId) ? "pin.fill" : "pin")
                                    .font(.title3)
                                    .foregroundStyle(store.transitColor)
                            }
                        }
                        
                        Button {
                            store.send(.saveTapped, animation: .default)
                        } label: {
                            Image(systemName: store.isSaved ? "bookmark.fill" : "bookmark")
                                .font(.title3)
                                .foregroundStyle(store.transitColor)
                        }
                        .accessibilityLabel(store.isSaved ? "Remove saved stop" : "Save stop")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let formattedDistance = store.formattedDistance {
                Label(
                    formattedDistance,
                    systemImage: "location.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.isSwipeable {
                TabView(selection: directionSelection) {
                    directionPage(directionId: 0)
                        .tag(0)

                    directionPage(directionId: 1)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 92)
                .sensoryFeedback(.selection, trigger: store.activeDirectionId)
            } else {
                directionPage(directionId: store.activeDirectionId)
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private var liveActivityButton: some View {
        Button {
            store.send(.liveActivityTapped)
        } label: {
            Image(systemName: "play.circle")
                .font(.title3)
                .foregroundStyle(store.transitColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Launch Live Activity")
        .help("Launch Live Activity")
        .contextMenu {
            Button {
                store.send(.liveActivityTapped)
            } label: {
                Label("Launch Live Activity", systemImage: "play.fill")
            }
        }
    }

    private var directionSelection: Binding<Int> {
        Binding(
            get: { store.activeDirectionId },
            set: { store.send(.directionSelected($0), animation: .snappy) }
        )
    }

    private func directionPage(directionId: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                let destination = destinationText(for: directionId)
                if !destination.isEmpty {
                    Image(systemName: "arrow.right")
                    Text(destination)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            predictionsBlock(directionId: directionId)

            if store.isSwipeable {
                HStack(spacing: 6) {
                    Spacer()
                    Circle()
                        .fill(store.transitColor.opacity(store.activeDirectionId == 0 ? 1.0 : 0.4))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(store.transitColor.opacity(store.activeDirectionId == 1 ? 1.0 : 0.4))
                        .frame(width: 6, height: 6)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func destinationText(for directionId: Int) -> String {
        guard store.target.directionDestinations.indices.contains(directionId) else {
            return directionId == 0 ? "Outbound" : "Inbound"
        }
        let destination = store.target.directionDestinations[directionId]
        return destination.isEmpty
            ? (directionId == 0 ? "Outbound" : "Inbound")
            : destination
    }

    @ViewBuilder
    private func predictionsBlock(directionId: Int) -> some View {
        let predictions = store.predictionSnapshots[directionId]?.predictions ?? []
        let isFetching = store.fetchingDirections.contains(directionId)

        HStack {
            if isFetching && predictions.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("Loading predictions...")
                    .font(.subheadline)
                    .opacity(0.8)
            } else if predictions.isEmpty {
                Text("No more departures scheduled today")
                    .font(.subheadline)
                    .opacity(0.8)
            } else {
                timesRow(
                    times: predictions,
                    color: store.transitColor,
                    foregroundColor: store.transitForegroundColor
                )
            }
        }
    }
    
    @ViewBuilder
    private func timesRow(times: [TransitPrediction], color: Color, foregroundColor: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(times, id: \.predictionId) { prediction in
                let bgStyle = AnyShapeStyle(color.gradient)
                let displayTime = prediction.display
                
                HStack(spacing: 4) {
                    if displayTime.lowercased().contains("stopped") {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Stopped")
                    } else {
                        Text(displayTime)
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
                .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
    }
}

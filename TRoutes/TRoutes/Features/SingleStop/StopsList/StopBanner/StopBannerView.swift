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
            HStack(alignment: .center, spacing: 12) {
                let transitType = store.target.transitType
                Image(systemName: transitType.iconName)
                    .font(.title2)
                    .foregroundStyle(store.transitColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.target.stopName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        if store.activeDirectionId < store.target.directionDestinations.count {
                            let destination = store.target.directionDestinations[store.activeDirectionId]
                            if !destination.isEmpty {
                                Image(systemName: "arrow.right")
                                Text(destination)
                            } else {
                                Text(store.activeDirectionId == 0 ? "Outbound" : "Inbound")
                            }
                        } else {
                            Text(store.activeDirectionId == 0 ? "Outbound" : "Inbound")
                        }
                    }
                    .font(.caption)
                    .opacity(0.8)

                    if let distance = store.distance {
                        Label(
                            Measurement(value: distance, unit: UnitLength.meters)
                                .formatted(.measurement(width: .abbreviated, usage: .road)),
                            systemImage: "location.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if store.target.isDirectionLocked {
                    Button {
                        store.send(.pinTapped, animation: .default)
                    } label: {
                        Image(systemName: "pin.fill")
                            .font(.title3)
                            .foregroundStyle(store.transitColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 16) {
                        Button {
                            store.send(.pinTapped, animation: .default)
                        } label: {
                            Image(systemName: store.pinnedDirections.contains(store.activeDirectionId) ? "pin.fill" : "pin")
                                .font(.title3)
                                .foregroundStyle(store.transitColor)
                        }
                        
                        Button {
                            store.send(.saveTapped, animation: .default)
                        } label: {
                            Image(systemName: store.isSaved ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(store.transitColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Predictions Block
            HStack {
                if store.isFetching && store.predictions.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading predictions...")
                        .font(.subheadline)
                        .opacity(0.8)
                } else if store.predictions.isEmpty {
                    Text("No upcoming departures")
                        .font(.subheadline)
                        .opacity(0.8)
                } else {
                    timesRow(times: store.predictions, color: store.transitColor, foregroundColor: store.transitForegroundColor)
                }
            }
            
            // Swipe Indicator Dots — only shown for swipeable stops
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
                .padding(.top, 4)
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if abs(value.translation.width) > 20 {
                        store.send(.switchDirectionTapped, animation: .spring(response: 0.4, dampingFraction: 0.8))
                    }
                }
        )
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
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

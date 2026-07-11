//
//  DebugDashboardView.swift
//  TRoutes
//
//  Created by Adam Post on 7/7/26.
//

import SwiftUI
import ComposableArchitecture

struct DebugDashboardView: View {
    let store: StoreOf<DebugDashboardFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Debug", systemImage: "ladybug.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(.red)

                Spacer()

                Text(store.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let journey = store.journey {
                VStack(alignment: .leading, spacing: 8) {
                    debugSection(
                        "Journey",
                        rows: [
                            ("Route", journey.route.name),
                            ("Movement", value(journey.movementStatus)),
                            ("Monitoring", value(journey.monitoringMode)),
                            ("Pending departure", journey.pendingDepartureConfirmation ? "true" : "false"),
                            ("Prediction", predictionText(journey.predictionState))
                        ]
                    )

                    if let currentLeg = journey.currentLeg {
                        debugSection(
                            "Current Leg",
                            rows: [
                                ("Route ID", currentLeg.mbtaRouteId),
                                ("Direction", "\(currentLeg.mbtaDirectionId)"),
                                ("Transit", currentLeg.transitType.rawValue),
                                ("Pattern", currentLeg.selectedPatternId),
                                ("Stops", "\(currentLeg.stops.count)"),
                                ("Origin index", "\(currentLeg.originPatternStopIndex)"),
                                ("Destination index", "\(currentLeg.destinationPatternStopIndex)")
                            ]
                        )
                    }

                    debugSection(
                        "Stops",
                        rows: [
                            ("Previous", stopSummary(journey.previousStop)),
                            ("Current", stopSummary(journey.currentStop)),
                            ("Next", stopSummary(journey.nextStop))
                        ]
                    )

                    if let currentStop = journey.currentStop {
                        debugSection(
                            "Current Stop",
                            rows: [
                                ("MBTA stop", currentStop.mbtaStopId),
                                ("Platform", currentStop.platformId),
                                ("Station", currentStop.stationId),
                                ("Route", currentStop.mbtaRouteId),
                                ("Direction", "\(currentStop.mbtaDirectionId)"),
                                ("Role", value(currentStop.journeyRole)),
                                ("Stop type", value(currentStop.stopType)),
                                ("Transit", currentStop.transitType.rawValue),
                                ("Monitoring", value(currentStop.monitoringMode)),
                                ("Leg stop index", "\(currentStop.legStopIndex)"),
                                ("Pattern stop index", "\(currentStop.patternStopIndex)"),
                                ("Pattern edge", "\(currentStop.patternEdgeSequenceNumber)"),
                                ("Overlaps next", currentStop.overlapsWithNext ? "true" : "false"),
                                ("Coordinate", coordinateText(currentStop))
                            ]
                        )
                    }
                }
            } else {
                Text("No active journey state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.red.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal)
    }

    private func debugSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)

                    Text(value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stopSummary(_ stop: ResolvedStop?) -> String {
        guard let stop else { return "nil" }
        return "\(stop.stopName) • \(stop.mbtaStopId) • \(stop.transitType.rawValue) • \(value(stop.monitoringMode))"
    }

    private func predictionText(_ predictionState: PredictionState?) -> String {
        guard let predictionState else { return "not needed" }
        switch predictionState.loadingState {
        case let .loading(stopId):
            return "loading \(stopId)"
        case let .loaded(stopId, times):
            return "loaded \(stopId): \(times.joined(separator: ", "))"
        case let .unavailable(stopId, message):
            return "unavailable \(stopId): \(message)"
        }
    }

    private func coordinateText(_ stop: ResolvedStop) -> String {
        "\(String(format: "%.5f", stop.latitude)), \(String(format: "%.5f", stop.longitude))"
    }

    private func value<T>(_ value: T) -> String {
        String(describing: value)
    }
}

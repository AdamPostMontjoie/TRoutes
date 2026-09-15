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
                        "Timing",
                        rows: timingRows(journey.timingState)
                    )

                    debugSection(
                        "Journey",
                        rows: [
                            ("Route", journey.route.name),
                            ("Movement", value(journey.movementStatus)),
                            ("Monitoring", value(journey.monitoringMode)),
                            ("Pending departure", journey.pendingDepartureConfirmation ? "true" : "false"),
                            ("Prediction (Active)", predictionText(journey.activeLegPrediction)),
                            ("Prediction (Transfer)", predictionText(journey.transferLegPrediction)),
                            ("Tracked vehicle", journey.trackedVehicleId ?? "nil"),
                            ("Arrived trains (A)", journey.activeLegPrediction?.arrivedTrains.isEmpty != false ? "none" : journey.activeLegPrediction!.arrivedTrains.map { $0.vehicleId }.joined(separator: ", ")),
                            ("Arrived trains (T)", journey.transferLegPrediction?.arrivedTrains.isEmpty != false ? "none" : journey.transferLegPrediction!.arrivedTrains.map { $0.vehicleId }.joined(separator: ", "))
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
                                ("Acceptable", currentLeg.acceptableRouteIds.joined(separator: ", ")),
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
                                ("Platform", currentStop.platformId),
                                ("Station", currentStop.stationId),
                                ("Route", currentStop.mbtaRouteId),
                                ("Role", value(currentStop.journeyRole)),
                                ("Monitoring", value(currentStop.monitoringMode)),
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

    private func timingRows(
        _ timingState: JourneyTimingState
    ) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Status", timingState.status.rawValue),
            ("Session", timingState.refreshSessionId?.uuidString ?? "nil"),
            ("Generation", "\(timingState.generation)"),
            ("Updated", dateText(timingState.updatedAt)),
            ("Current leg ETA", dateText(timingState.currentLegArrival)),
            ("Journey ETA", dateText(timingState.destinationArrival))
        ]

        if let recommendation = timingState.recommendedDeparture {
            rows.append(
                (
                    "Recommendation",
                    "\(dateText(recommendation.departureTime)) • \(recommendation.timeSource.rawValue)"
                )
            )
            rows.append(
                (
                    "Recommended ETA",
                    dateText(recommendation.destinationArrivalTime)
                )
            )
            rows.append(
                (
                    "Recommended trips",
                    recommendation.selectedTripIds.joined(separator: ", ")
                )
            )
            rows.append(("Timing sources", recommendation.sourceComposition.rawValue))
        } else {
            rows.append(("Recommendation", "nil"))
        }

        if let connection = timingState.connection {
            rows.append(("Warning", connection.warning.rawValue))
            rows.append(
                (
                    "Connection",
                    "\(dateText(connection.arrival)) → \(dateText(connection.departure))"
                )
            )
            rows.append(
                ("Physical slack", durationText(connection.physicalSlack))
            )
            rows.append(
                ("Buffer slack", durationText(connection.bufferSlack))
            )
            rows.append(
                ("High consequence", connection.isHighConsequence ? "true" : "false")
            )
            rows.append(("Last service", connection.isLastService ? "true" : "false"))
            rows.append(
                (
                    "Next alternative",
                    dateText(connection.nextAlternativeDeparture)
                )
            )
        } else {
            rows.append(("Warning", "none"))
        }

        return rows
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        "\(Int(duration.rounded())) sec"
    }

    private func coordinateText(_ stop: ResolvedStop) -> String {
        "\(String(format: "%.5f", stop.latitude)), \(String(format: "%.5f", stop.longitude))"
    }

    private func value<T>(_ value: T) -> String {
        String(describing: value)
    }
}

//
//  StopPredictionCache.swift
//  TRoutes
//
//  Created by Adam Post on 8/23/26.
//

import ComposableArchitecture
import Foundation

struct StopPredictionKey: Equatable, Hashable, Sendable {
    let stationId: String
    let routeId: String
    let directionId: Int
}

struct StopPredictionSnapshot: Equatable, Sendable {
    let predictions: [TransitPrediction]
    let fetchedAt: Date

    func isFresh(at date: Date, maxAge: TimeInterval) -> Bool {
        date.timeIntervalSince(fetchedAt) < maxAge
    }
}

actor StopPredictionCache {
    static let shared = StopPredictionCache()

    @Dependency(\.mbtaClient) private var mbtaClient

    private var snapshots: [StopPredictionKey: StopPredictionSnapshot] = [:]
    private var inFlightRequests: [StopPredictionKey: Task<StopPredictionSnapshot, Error>] = [:]
    private var lastAttemptDates: [StopPredictionKey: Date] = [:]

    func predictions(
        for key: StopPredictionKey,
        maxAge: TimeInterval = 15
    ) async throws -> StopPredictionSnapshot {
        let now = Date()
        if let snapshot = snapshots[key], snapshot.isFresh(at: now, maxAge: maxAge) {
            return snapshot
        }

        if let request = inFlightRequests[key] {
            return try await request.value
        }

        if let lastAttemptDate = lastAttemptDates[key],
           now.timeIntervalSince(lastAttemptDate) < maxAge {
            throw StopPredictionCacheError.retryTooSoon
        }

        lastAttemptDates[key] = now

        let request = Task { [mbtaClient] in
            let target = StopBannerPredictionRequest(
                predictionRouteId: key.routeId,
                predictionStopIds: [key.stationId],
                predictionDirectionId: key.directionId
            )
            var predictions = try await mbtaClient.fetchTransitTimes(
                target,
                [key.routeId],
                .predictionRefresh
            )
            if predictions.isEmpty {
                let schedules = try await mbtaClient.fetchSchedule(target, .predictionRefresh)
                predictions = schedules.map(\.asPrediction)
            }
            return StopPredictionSnapshot(predictions: predictions, fetchedAt: Date())
        }
        inFlightRequests[key] = request

        do {
            let snapshot = try await request.value
            snapshots[key] = snapshot
            lastAttemptDates[key] = snapshot.fetchedAt
            inFlightRequests[key] = nil
            return snapshot
        } catch {
            lastAttemptDates[key] = Date()
            inFlightRequests[key] = nil
            throw error
        }
    }
}

private enum StopPredictionCacheError: Error {
    case retryTooSoon
}

private struct StopBannerPredictionRequest: PredictionTarget, Sendable {
    let predictionRouteId: String
    let predictionStopIds: [String]
    let predictionDirectionId: Int
}
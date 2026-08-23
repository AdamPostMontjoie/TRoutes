//
//  StopLiveActivityManager.swift
//  TRoutes
//
//  Created by Adam Post on 8/23/26.
//

import ActivityKit
import Foundation

struct StopLiveActivityRequest: Equatable, Sendable {
    let key: StopPredictionKey
    let stopName: String
    let routeBadge: String
    let routeDetail: String?
    let destination: String
    let colorHex: String
    let foregroundColorHex: String
    let initialPredictions: [String]

    init(
        key: StopPredictionKey,
        stopName: String,
        routePresentation: RoutePresentation,
        destination: String,
        transitType: TransitType,
        initialPredictions: [String]
    ) {
        self.key = key
        self.stopName = stopName
        self.routeBadge = routePresentation.badgeText
        self.routeDetail = routePresentation.detailText
        self.destination = destination
        self.initialPredictions = initialPredictions

        if routePresentation.badgeText.hasPrefix("SL") {
            self.colorHex = "#7C878E"
            self.foregroundColorHex = "#000000"
            return
        }

        switch transitType {
        case .redLine, .mattapan:
            self.colorHex = "#DA291C"
        case .orangeLine:
            self.colorHex = "#ED8B00"
        case .greenLine:
            self.colorHex = "#00843D"
        case .blueLine:
            self.colorHex = "#003DA5"
        case .commuterRail:
            self.colorHex = "#80276C"
        case .bus:
            self.colorHex = "#FFC72C"
        case .ferry:
            self.colorHex = "#008EAA"
        }
        self.foregroundColorHex = transitType == .bus ? "#000000" : "#FFFFFF"
    }
}

enum StopLiveActivityError: Error, Equatable {
    case activitiesDisabled
    case locationUnavailable
    case requestFailed
}

actor StopLiveActivityManager {
    static let shared = StopLiveActivityManager()

    private var refreshTask: Task<Void, Never>?
    private var activityStateTask: Task<Void, Never>?
    private var activeActivityId: String?
    private var activeKey: StopPredictionKey?

    func start(_ request: StopLiveActivityRequest) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw StopLiveActivityError.activitiesDisabled
        }

        await end()

        let attributes = StopActivityAttributes(
            stationId: request.key.stationId,
            routeId: request.key.routeId,
            directionId: request.key.directionId,
            stopName: request.stopName,
            routeBadge: request.routeBadge,
            routeDetail: request.routeDetail,
            destination: request.destination,
            colorHex: request.colorHex,
            foregroundColorHex: request.foregroundColorHex
        )
        let state = StopActivityAttributes.ContentState(
            predictions: request.initialPredictions,
            updatedAt: Date()
        )

        let activity: Activity<StopActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)),
                pushType: nil
            )
        } catch {
            throw StopLiveActivityError.requestFailed
        }

        guard await NearbyStopsManager.shared.startLiveActivityBackgroundSession() else {
            await activity.end(nil, dismissalPolicy: .immediate)
            throw StopLiveActivityError.locationUnavailable
        }

        activeActivityId = activity.id
        activeKey = request.key
        observeActivityState(activity)
        startRefreshing(key: request.key)
    }

    func end() async {
        activityStateTask?.cancel()

        for activity in Activity<StopActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        await stopMonitoring()
    }

    nonisolated func stopSessionTimeoutAsync() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for activity in Activity<StopActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.5)
    }

    private func startRefreshing(key: StopPredictionKey) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                guard activeKey == key else { return }

                if let snapshot = try? await StopPredictionCache.shared.predictions(for: key) {
                    await update(key: key, snapshot: snapshot)
                }

                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func observeActivityState(_ activity: Activity<StopActivityAttributes>) {
        activityStateTask?.cancel()
        let activityId = activity.id
        activityStateTask = Task { [weak self] in
            guard let observedActivity = Activity<StopActivityAttributes>.activities.first(where: {
                $0.id == activityId
            }) else {
                await self?.activityDidEnd(id: activityId)
                return
            }

            for await state in observedActivity.activityStateUpdates {
                switch state {
                case .dismissed, .ended:
                    await self?.activityDidEnd(id: activityId)
                    return
                case .active, .stale, .pending:
                    continue
                @unknown default:
                    continue
                }
            }
        }
    }

    private func activityDidEnd(id: String) async {
        guard activeActivityId == id else { return }
        await stopMonitoring()
    }

    private func stopMonitoring() async {
        refreshTask?.cancel()
        refreshTask = nil
        activityStateTask?.cancel()
        activityStateTask = nil
        activeActivityId = nil
        activeKey = nil
        await NearbyStopsManager.shared.stopLiveActivityBackgroundSession()
    }

    private func update(key: StopPredictionKey, snapshot: StopPredictionSnapshot) async {
        let state = StopActivityAttributes.ContentState(
            predictions: snapshot.predictions.map(\.display),
            updatedAt: snapshot.fetchedAt
        )
        let content = ActivityContent(
            state: state,
            staleDate: snapshot.fetchedAt.addingTimeInterval(45)
        )

        for activity in Activity<StopActivityAttributes>.activities where
            activity.attributes.stationId == key.stationId
                && activity.attributes.routeId == key.routeId
                && activity.attributes.directionId == key.directionId {
            await activity.update(content)
        }
    }

}

//
//  JourneyPredictionSliceTests.swift
//  TRoutesTests
//

import Foundation
import Testing
@testable import TRoutes

struct JourneyPredictionSliceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func threeLiveCallsDoNotUseSchedules() async {
        let live = [
            call("live-3", minutesAway: 15, source: .prediction),
            call("live-1", minutesAway: 5, source: .prediction),
            call("live-4", minutesAway: 20, source: .prediction),
            call("live-2", minutesAway: 10, source: .prediction)
        ]
        let raw = UnmergedTimingCalls(
            predictionCalls: live,
            scheduleCalls: [call("schedule-1", minutesAway: 7, source: .schedule)]
        )

        let slice = await JourneyTimingEngine.shared.createPredictionSlice(
            for: target(), rawCalls: raw, now: now
        )

        #expect(slice.displayPredictions.map(\.tripId) == ["live-1", "live-2", "live-3"])
        #expect(slice.livePredictions.map(\.tripId) == ["live-1", "live-2", "live-3", "live-4"])
        #expect(slice.displayPredictions.allSatisfy { $0.display.contains("min") })
    }

    @Test func twoLiveCallsFillWithOneDistinctSchedule() async {
        let raw = UnmergedTimingCalls(
            predictionCalls: [
                call("live-1", minutesAway: 5, source: .prediction),
                call("live-2", minutesAway: 15, source: .prediction)
            ],
            scheduleCalls: [
                call("live-1", minutesAway: 7, source: .schedule),
                call("wrong-direction", minutesAway: 8, source: .schedule, direction: 1),
                call("canceled", minutesAway: 9, source: .schedule, status: "Canceled"),
                call("schedule-1", minutesAway: 10, source: .schedule),
                call("schedule-2", minutesAway: 20, source: .schedule)
            ]
        )

        let slice = await JourneyTimingEngine.shared.createPredictionSlice(
            for: target(), rawCalls: raw, now: now
        )

        #expect(slice.displayPredictions.map(\.tripId) == ["live-1", "schedule-1", "live-2"])
        #expect(slice.livePredictions.map(\.tripId) == ["live-1", "live-2"])
        #expect(slice.displayPredictions[0].display.contains("min"))
        #expect(!slice.displayPredictions[1].display.contains("min"))
        #expect(slice.displayPredictions[2].display.contains("min"))
    }

    @Test func noLiveCallsUseOnlyFutureSchedulesUpToThree() async {
        let raw = UnmergedTimingCalls(
            predictionCalls: [],
            scheduleCalls: [
                call("past", minutesAway: -1, source: .schedule),
                call("schedule-1", minutesAway: 5, source: .schedule),
                call("schedule-2", minutesAway: 10, source: .schedule)
            ]
        )

        let slice = await JourneyTimingEngine.shared.createPredictionSlice(
            for: target(), rawCalls: raw, now: now
        )

        #expect(slice.displayPredictions.map(\.tripId) == ["schedule-1", "schedule-2"])
        #expect(slice.livePredictions.isEmpty)
    }

    private func target() -> TimingPredictionTargetPlan {
        TimingPredictionTargetPlan(
            endpoint: TimingEndpointPlan(
                resolvedStopId: UUID(),
                canonicalStopId: "boarding",
                acceptableStopIds: ["boarding"]
            ),
            acceptableRouteDirections: [TimingRouteDirection(routeId: "route", directionId: 0)]
        )
    }

    private func call(
        _ tripId: String,
        minutesAway: Int,
        source: TimingSource,
        direction: Int = 0,
        status: String? = nil
    ) -> TripStopTiming {
        let departure = now.addingTimeInterval(TimeInterval(minutesAway * 60))
        let times = StopTimes(arrival: nil, departure: departure)
        return TripStopTiming(
            key: TripStopKey(tripId: tripId, stopId: "boarding", stopSequence: 1),
            routeId: "route",
            directionId: direction,
            vehicleId: source == .prediction ? "vehicle-\(tripId)" : nil,
            headsign: "Destination",
            isLastTrip: nil,
            scheduleId: source == .schedule ? "schedule-\(tripId)" : nil,
            predictionId: source == .prediction ? "prediction-\(tripId)" : nil,
            scheduled: source == .schedule ? times : nil,
            predicted: source == .prediction ? times : nil,
            status: status,
            scheduleRelationship: nil,
            availability: source == .prediction ? .predicted : .scheduledOnly
        )
    }
}

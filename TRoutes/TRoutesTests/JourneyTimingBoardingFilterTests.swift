import Foundation
import Testing
@testable import TRoutes

struct JourneyTimingBoardingFilterTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func optionsUseEveryPredictionAndKeepScheduledDestinationEstimates() async {
        let live = [5, 10, 15, 20].map {
            call("live-\($0)", minutesAway: $0, source: .prediction)
        }
        let schedules = [
            call("before-live", minutesAway: 3, source: .schedule),
            call("between-live", minutesAway: 12, source: .schedule),
            call("after-third", minutesAway: 17, source: .schedule),
            call("at-cutoff", minutesAway: 20, source: .schedule),
            call("after-live", minutesAway: 25, source: .schedule),
            call("live-5", minutesAway: 30, source: .schedule)
        ]
        let options = await options(for: leg(), origins: live + schedules, currentPredictions: live)

        #expect(options.map(\.tripId) == ["live-5", "live-10", "live-15", "live-20", "after-live"])
        #expect(options.prefix(4).allSatisfy { $0.boardingTime.source == .prediction })
        #expect(options.allSatisfy { $0.arrivalTime.source == .schedule })
    }

    @Test func cutoffMatchesOnlyTheLegsBoardingStopAndAllowedServices() async {
        let live = call("live", minutesAway: 5, source: .prediction)
        let unrelated = [
            call("other-stop", minutesAway: 40, source: .prediction, stop: "elsewhere"),
            call("other-direction", minutesAway: 50, source: .prediction, direction: 1),
            call("other-route", minutesAway: 60, source: .prediction, route: "other-route")
        ]
        let scheduled = call("after-live", minutesAway: 10, source: .schedule)
        let options = await options(
            for: leg(), origins: [live, scheduled], currentPredictions: [live] + unrelated
        )

        #expect(options.map(\.tripId) == ["live", "after-live"])
    }

    @Test func currentResponseSetsCutoffWithoutExtendingItToRetainedHistory() async {
        let live = call("live", minutesAway: 5, source: .prediction)
        let retained = call("retained", minutesAway: 30, source: .prediction, availability: .predictionLost)
        let scheduled = call("after-live", minutesAway: 10, source: .schedule)
        let options = await options(
            for: leg(), origins: [live, scheduled, retained], currentPredictions: [live]
        )

        #expect(options.map(\.tripId) == ["live", "after-live", "retained"])
    }

    @Test func noPredictionsKeepScheduleFallbackAndOnboardTripIsPreserved() async {
        let scheduled = call("schedule", minutesAway: 3, source: .schedule)
        let fallback = await options(for: leg(), origins: [scheduled], currentPredictions: [])
        #expect(fallback.map(\.tripId) == ["schedule"])

        let onboard = call("onboard", minutesAway: -10, source: .schedule)
        let live = call("live", minutesAway: 5, source: .prediction)
        let destination = call("onboard", minutesAway: 20, source: .schedule, stop: "destination")
        let onboardOptions = await JourneyTimingEngine.shared.buildTripOptions(
            for: leg(), from: [onboard, destination, live], currentPredictionCalls: [live],
            isInProgressLeg: true, onboardTripId: "onboard", now: now
        )
        #expect(onboardOptions.map(\.tripId) == ["onboard"])
    }

    @Test func laterScheduleCompletesJourneyWhenLiveConnectionsCannotBeCaught() async throws {
        let feederOrigin = call("feeder", minutesAway: 1, source: .prediction)
        let feederOptions = await options(
            for: leg(), origins: [feederOrigin], currentPredictions: [feederOrigin]
        )
        let feeder = try #require(feederOptions.first)
        let nextLeg = leg(origin: "transfer", destination: "final")
        let live = [5, 10].map {
            call("live-\($0)", minutesAway: $0, source: .prediction, stop: "transfer")
        }
        let schedules = [
            call("within-live", minutesAway: 8, source: .schedule, stop: "transfer"),
            call("after-live", minutesAway: 20, source: .schedule, stop: "transfer")
        ]
        let nextOptions = await options(for: nextLeg, origins: live + schedules, currentPredictions: live)
        let journeys = nextOptions.compactMap { next -> TimedJourney? in
            let transfer = TransferTiming(
                arrivingLegId: feeder.legId, departingLegId: next.legId, stationId: "transfer",
                arrival: feeder.arrival, departure: next.departure,
                requirement: TransferRequirement(minimumTransferTime: 3 * 60, preferredReliabilityBuffer: 0),
                nextAlternativeDeparture: nil, isHighConsequence: false, isLastService: false
            )
            return TimedJourney(legs: [feeder, next], transfers: [transfer], warnings: [])
        }

        #expect(nextOptions.map(\.tripId) == ["live-5", "live-10", "after-live"])
        #expect(journeys.count == 1)
        #expect(journeys.first?.legs.last?.tripId == "after-live")
    }

    private func options(for leg: TimingLegPlan, origins: [TripStopTiming], currentPredictions: [TripStopTiming]) async -> [LegTripOption] {
        let destinations = origins.map { origin in
            call(
                origin.key.tripId,
                minutesAway: Int(origin.effectiveDeparture!.timeIntervalSince(now) / 60) + 10,
                source: .schedule, stop: leg.destination.canonicalStopId
            )
        }
        return await JourneyTimingEngine.shared.buildTripOptions(
            for: leg, from: origins + destinations, currentPredictionCalls: currentPredictions,
            isInProgressLeg: false, onboardTripId: nil, now: now
        )
    }

    private func leg(origin: String = "boarding", destination: String = "destination") -> TimingLegPlan {
        TimingLegPlan(
            id: UUID(), acceptableRouteDirections: [TimingRouteDirection(routeId: "route", directionId: 0)],
            origin: TimingEndpointPlan(resolvedStopId: UUID(), canonicalStopId: origin, acceptableStopIds: []),
            destination: TimingEndpointPlan(resolvedStopId: UUID(), canonicalStopId: destination, acceptableStopIds: [])
        )
    }

    private func call(
        _ trip: String, minutesAway: Int, source: TimingSource,
        stop: String = "boarding", direction: Int = 0, route: String = "route",
        availability: StopCallAvailability? = nil
    ) -> TripStopTiming {
        let time = now.addingTimeInterval(TimeInterval(minutesAway * 60))
        let times = StopTimes(arrival: time, departure: time)
        return TripStopTiming(
            key: TripStopKey(tripId: trip, stopId: stop, stopSequence: stop == "boarding" || stop == "transfer" ? 1 : 2),
            routeId: route, directionId: direction, vehicleId: nil, headsign: nil, isLastTrip: nil,
            scheduleId: source == .schedule ? "schedule-\(trip)-\(stop)" : nil,
            predictionId: source == .prediction ? "prediction-\(trip)-\(stop)" : nil,
            scheduled: source == .schedule ? times : nil,
            predicted: source == .prediction ? times : nil,
            status: nil, scheduleRelationship: nil,
            availability: availability ?? (source == .prediction ? .predicted : .scheduledOnly)
        )
    }
}

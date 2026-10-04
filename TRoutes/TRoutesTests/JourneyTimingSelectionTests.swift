//
//  JourneyTimingSelectionTests.swift
//  TRoutesTests
//

import Foundation
import Testing
@testable import TRoutes

struct JourneyTimingSelectionTests {
    @Test func timingWithoutCompleteETAIsUnavailable() async {
        let status = await JourneyTimingEngine.shared.timingStatus(
            for: JourneyTimingSelection(
                etaJourney: nil,
                recommendedJourney: nil,
                currentLegOption: nil,
                monitoredConnection: nil
            )
        )

        #expect(status == .unavailable)
    }

    @Test func retainedMissingPredictionMakesETAStale() async throws {
        let now = Date(timeIntervalSince1970: 5_000)
        let option = try #require(makeOption(
            legId: UUID(),
            tripId: "temporarily-missing",
            originStopId: "origin",
            destinationStopId: "destination",
            departure: now.addingTimeInterval(5 * 60),
            arrival: now.addingTimeInterval(15 * 60),
            availability: .predictionLost
        ))
        let journey = try #require(TimedJourney(
            legs: [option],
            transfers: [],
            warnings: []
        ))
        let status = await JourneyTimingEngine.shared.timingStatus(
            for: JourneyTimingSelection(
                etaJourney: journey,
                recommendedJourney: nil,
                currentLegOption: option,
                monitoredConnection: nil
            )
        )

        #expect(status == .stale)
    }

    @Test func atStopUsesFirstTripForETAAndWatchesMissedEarlierConnection() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let firstLegId = UUID()
        let secondLegId = UUID()
        let firstTrip = try #require(makeOption(
            legId: firstLegId,
            tripId: "OL-1",
            originStopId: "origin",
            destinationStopId: "transfer-arrival",
            departure: now.addingTimeInterval(3 * 60),
            arrival: now.addingTimeInterval(23 * 60)
        ))
        let missedTrip = try #require(makeOption(
            legId: secondLegId,
            tripId: "CR-1",
            originStopId: "transfer-departure",
            destinationStopId: "destination",
            departure: now.addingTimeInterval(25 * 60),
            arrival: now.addingTimeInterval(60 * 60)
        ))
        let viableTrip = try #require(makeOption(
            legId: secondLegId,
            tripId: "CR-2",
            originStopId: "transfer-departure",
            destinationStopId: "destination",
            departure: now.addingTimeInterval(90 * 60),
            arrival: now.addingTimeInterval(125 * 60)
        ))

        let requirement = TransferRequirement(
            minimumTransferTime: 2 * 60,
            preferredReliabilityBuffer: 60
        )
        let missedConnection = makeConnection(
            from: firstTrip,
            to: missedTrip,
            requirement: requirement,
            nextAlternativeDeparture: viableTrip.departure
        )
        let viableConnection = makeConnection(
            from: firstTrip,
            to: viableTrip,
            requirement: requirement,
            nextAlternativeDeparture: nil
        )
        let viableJourney = try #require(TimedJourney(
            legs: [firstTrip, viableTrip],
            transfers: [viableConnection],
            warnings: []
        ))
        let queryPlan = makeQueryPlan(
            firstLegId: firstLegId,
            secondLegId: secondLegId
        )
        let graph = TimingConnectionGraph(connectionsByOption: [
            OptionConnectionKey(
                arrivingOptionId: firstTrip.id,
                departingOptionId: missedTrip.id
            ): missedConnection,
            OptionConnectionKey(
                arrivingOptionId: firstTrip.id,
                departingOptionId: viableTrip.id
            ): viableConnection
        ])

        let selection = await JourneyTimingEngine.shared.selectTiming(
            context: JourneyTimingContext(
                timingLegId: firstLegId,
                phase: .atBoardingStop
            ),
            queryPlan: queryPlan,
            completeJourneys: [viableJourney],
            optionsByLeg: [
                firstLegId: [firstTrip],
                secondLegId: [missedTrip, viableTrip]
            ],
            coverageByLeg: [:],
            connectionGraph: graph
        )

        #expect(selection.recommendedJourney == nil)
        #expect(selection.currentLegOption?.tripId == "OL-1")
        #expect(selection.etaJourney?.destinationArrival == viableTrip.arrival)
        #expect(selection.monitoredConnection?.departure == missedTrip.departure)
        #expect(selection.monitoredConnection?.warning == .likelyMiss)
    }

    @Test func approachingStopChoosesLatestBufferedFeederForSameArrival() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let firstLegId = UUID()
        let secondLegId = UUID()
        let earlyFeeder = try #require(makeOption(
            legId: firstLegId,
            tripId: "OL-1",
            originStopId: "origin",
            destinationStopId: "transfer-arrival",
            departure: now.addingTimeInterval(3 * 60),
            arrival: now.addingTimeInterval(7 * 60)
        ))
        let lateFeeder = try #require(makeOption(
            legId: firstLegId,
            tripId: "OL-2",
            originStopId: "origin",
            destinationStopId: "transfer-arrival",
            departure: now.addingTimeInterval(8 * 60),
            arrival: now.addingTimeInterval(13 * 60)
        ))
        let downstream = try #require(makeOption(
            legId: secondLegId,
            tripId: "CR-1",
            originStopId: "transfer-departure",
            destinationStopId: "destination",
            departure: now.addingTimeInterval(25 * 60),
            arrival: now.addingTimeInterval(60 * 60)
        ))
        let requirement = TransferRequirement(
            minimumTransferTime: 3 * 60,
            preferredReliabilityBuffer: 5 * 60
        )
        let earlyJourney = try #require(TimedJourney(
            legs: [earlyFeeder, downstream],
            transfers: [makeConnection(
                from: earlyFeeder,
                to: downstream,
                requirement: requirement,
                nextAlternativeDeparture: nil
            )],
            warnings: []
        ))
        let lateJourney = try #require(TimedJourney(
            legs: [lateFeeder, downstream],
            transfers: [makeConnection(
                from: lateFeeder,
                to: downstream,
                requirement: requirement,
                nextAlternativeDeparture: nil
            )],
            warnings: []
        ))

        let selection = await JourneyTimingEngine.shared.selectTiming(
            context: JourneyTimingContext(
                timingLegId: firstLegId,
                phase: .approachingBoarding
            ),
            queryPlan: makeQueryPlan(
                firstLegId: firstLegId,
                secondLegId: secondLegId
            ),
            completeJourneys: [earlyJourney, lateJourney],
            optionsByLeg: [
                firstLegId: [earlyFeeder, lateFeeder],
                secondLegId: [downstream]
            ],
            coverageByLeg: [:],
            connectionGraph: TimingConnectionGraph(connectionsByOption: [:])
        )

        #expect(selection.recommendedJourney?.legs.first?.tripId == "OL-2")
        #expect(selection.etaJourney == selection.recommendedJourney)
        #expect(selection.monitoredConnection == nil)
    }

    @Test func earlierPossibleTightJourneyBeatsLaterBufferedJourney() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let feeder = try #require(makeOption(
            legId: UUID(), tripId: "OL", originStopId: "origin",
            destinationStopId: "transfer", departure: now.addingTimeInterval(3 * 60),
            arrival: now.addingTimeInterval(23 * 60)
        ))
        let earlyTrain = try #require(makeOption(
            legId: UUID(), tripId: "CR-early", originStopId: "transfer",
            destinationStopId: "destination", departure: now.addingTimeInterval(27 * 60),
            arrival: now.addingTimeInterval(60 * 60)
        ))
        let laterTrain = try #require(makeOption(
            legId: earlyTrain.legId, tripId: "CR-later", originStopId: "transfer",
            destinationStopId: "destination", departure: now.addingTimeInterval(40 * 60),
            arrival: now.addingTimeInterval(75 * 60)
        ))
        let requirement = TransferRequirement(minimumTransferTime: 3 * 60, preferredReliabilityBuffer: 5 * 60)
        let tightConnection = makeConnection(from: feeder, to: earlyTrain, requirement: requirement, nextAlternativeDeparture: laterTrain.departure)
        let bufferedConnection = makeConnection(from: feeder, to: laterTrain, requirement: requirement, nextAlternativeDeparture: nil)
        let tightJourney = try #require(TimedJourney(legs: [feeder, earlyTrain], transfers: [tightConnection], warnings: []))
        let bufferedJourney = try #require(TimedJourney(legs: [feeder, laterTrain], transfers: [bufferedConnection], warnings: []))

        #expect(tightConnection.isPhysicallyPossible)
        #expect(!tightConnection.meetsReliabilityBuffer)
        #expect(bufferedConnection.meetsReliabilityBuffer)
        #expect(JourneySelectionPolicy().selectRecommendation(from: [bufferedJourney, tightJourney]) == tightJourney)
    }

    @Test func selectedBoardingTimeKeepsSourceAndEventTogether() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let arrivalOnly = TripStopTiming(
            key: TripStopKey(tripId: "arrival-only", stopId: "origin", stopSequence: 1),
            routeId: "route", directionId: 0, vehicleId: nil, headsign: nil,
            isLastTrip: nil, scheduleId: "schedule", predictionId: "prediction",
            scheduled: StopTimes(arrival: nil, departure: now.addingTimeInterval(2 * 60)),
            predicted: StopTimes(arrival: now, departure: nil), status: nil,
            scheduleRelationship: nil, availability: .predicted
        )
        let predictionOption = try #require(makeOption(
            legId: UUID(), tripId: "prediction", originStopId: "origin",
            destinationStopId: "destination", departure: now,
            arrival: now.addingTimeInterval(10 * 60)
        ))

        #expect(arrivalOnly.selectedBoardingTime == SelectedStopTime(time: now, source: .prediction, event: .arrival))
        #expect(predictionOption.boardingTime == SelectedStopTime(time: now, source: .prediction, event: .arrival))
    }

    @Test func selectedArrivalTimeRecordsTheActualEndpointEvent() {
        let now = Date(timeIntervalSince1970: 45_000)
        let predictedArrival = TripStopTiming(
            key: TripStopKey(tripId: "trip", stopId: "destination", stopSequence: 2),
            routeId: "route", directionId: 0, vehicleId: nil, headsign: nil,
            isLastTrip: nil, scheduleId: "schedule", predictionId: "prediction",
            scheduled: StopTimes(arrival: now.addingTimeInterval(60), departure: nil),
            predicted: StopTimes(arrival: now, departure: now.addingTimeInterval(30)),
            status: nil, scheduleRelationship: nil, availability: .predicted
        )
        let predictedDeparture = TripStopTiming(
            key: predictedArrival.key, routeId: predictedArrival.routeId,
            directionId: predictedArrival.directionId, vehicleId: nil,
            headsign: nil, isLastTrip: nil, scheduleId: "schedule",
            predictionId: "prediction",
            scheduled: predictedArrival.scheduled,
            predicted: StopTimes(arrival: nil, departure: now.addingTimeInterval(30)),
            status: nil, scheduleRelationship: nil, availability: .predicted
        )

        #expect(predictedArrival.selectedArrivalTime == SelectedStopTime(time: now, source: .prediction, event: .arrival))
        #expect(predictedDeparture.selectedArrivalTime == SelectedStopTime(time: now.addingTimeInterval(30), source: .prediction, event: .departure))
    }

    private func makeOption(
        legId: UUID,
        tripId: String,
        originStopId: String,
        destinationStopId: String,
        departure: Date,
        arrival: Date,
        availability: StopCallAvailability = .predicted
    ) -> LegTripOption? {
        let origin = TripStopTiming(
            key: TripStopKey(
                tripId: tripId,
                stopId: originStopId,
                stopSequence: 1
            ),
            routeId: "route",
            directionId: 0,
            vehicleId: nil,
            headsign: nil,
            isLastTrip: nil,
            scheduleId: nil,
            predictionId: "prediction-\(tripId)-origin",
            scheduled: nil,
            predicted: StopTimes(arrival: departure, departure: departure),
            status: nil,
            scheduleRelationship: nil,
            availability: availability
        )
        let destination = TripStopTiming(
            key: TripStopKey(
                tripId: tripId,
                stopId: destinationStopId,
                stopSequence: 2
            ),
            routeId: "route",
            directionId: 0,
            vehicleId: nil,
            headsign: nil,
            isLastTrip: nil,
            scheduleId: nil,
            predictionId: "prediction-\(tripId)-destination",
            scheduled: nil,
            predicted: StopTimes(arrival: arrival, departure: arrival),
            status: nil,
            scheduleRelationship: nil,
            availability: availability
        )
        return LegTripOption(
            legId: legId,
            origin: origin,
            destination: destination
        )
    }

    private func makeConnection(
        from arrivingOption: LegTripOption,
        to departingOption: LegTripOption,
        requirement: TransferRequirement,
        nextAlternativeDeparture: Date?
    ) -> TransferTiming {
        TransferTiming(
            arrivingLegId: arrivingOption.legId,
            departingLegId: departingOption.legId,
            stationId: "transfer-station",
            arrival: arrivingOption.arrival,
            departure: departingOption.departure,
            requirement: requirement,
            nextAlternativeDeparture: nextAlternativeDeparture,
            isHighConsequence: false,
            isLastService: false
        )
    }

    private func makeQueryPlan(
        firstLegId: UUID,
        secondLegId: UUID
    ) -> TimingQueryPlan {
        let routeDirections = Set([
            TimingRouteDirection(routeId: "route", directionId: 0)
        ])
        return TimingQueryPlan(
            resolvedRouteId: UUID(),
            legs: [
                TimingLegPlan(
                    id: firstLegId,
                    acceptableRouteDirections: routeDirections,
                    origin: TimingEndpointPlan(
                        resolvedStopId: UUID(),
                        canonicalStopId: "origin",
                        acceptableStopIds: []
                    ),
                    destination: TimingEndpointPlan(
                        resolvedStopId: UUID(),
                        canonicalStopId: "transfer-arrival",
                        acceptableStopIds: []
                    )
                ),
                TimingLegPlan(
                    id: secondLegId,
                    acceptableRouteDirections: routeDirections,
                    origin: TimingEndpointPlan(
                        resolvedStopId: UUID(),
                        canonicalStopId: "transfer-departure",
                        acceptableStopIds: []
                    ),
                    destination: TimingEndpointPlan(
                        resolvedStopId: UUID(),
                        canonicalStopId: "destination",
                        acceptableStopIds: []
                    )
                )
            ]
        )
    }
}

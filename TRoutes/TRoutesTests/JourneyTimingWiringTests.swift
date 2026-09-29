//
//  JourneyTimingWiringTests.swift
//  TRoutesTests
//

import Foundation
import Testing
@testable import TRoutes

struct JourneyTimingWiringTests {
    @Test func sameStopTransferIncludesOneMinuteWalkingAllowance() {
        let leg = makeRoute().legs[0]
        let requirement = ConnectionTimingPolicy().transferRequirement(from: leg, to: leg)

        #expect(requirement.minimumTransferTime == 60)
        #expect(requirement.preferredReliabilityBuffer == 2 * 60)
    }

    @Test func boardingNoticeUsesEventRatherThanSourceForWording() throws {
        let leg = makeRoute().legs[0]
        let time = Date(timeIntervalSince1970: 50_000)
        let boardingTime = SelectedStopTime(time: time, source: .prediction, event: .departure)
        let recommendation = RecommendedDeparture(
            resolvedLegId: leg.id, tripId: "trip", boardingTime: boardingTime
        )
        let timing = JourneyTimingPlan(
            status: .current, selectedItinerary: nil, currentLeg: nil,
            recommendedDeparture: recommendation, monitoredConnection: nil
        )
        let details = try #require(BoardingNoticeDetails(recommendation: recommendation, timingPlan: timing, legs: [leg]))

        #expect(details.boardingTime == boardingTime)
    }

    @Test func approachingStopNoticeDoesNotCallDepartureAnArrival() throws {
        let leg = makeRoute().legs[0]
        let time = Date(timeIntervalSince1970: 55_000)
        let boardingTime = SelectedStopTime(time: time, source: .prediction, event: .departure)
        let fallbackLeg = JourneyLegTiming(
            resolvedLegId: leg.id, tripId: "trip", routeId: leg.mbtaRouteId,
            directionId: leg.mbtaDirectionId,
            originStopId: leg.startStop.mbtaStopId,
            destinationStopId: leg.endStop.mbtaStopId,
            boardingTime: boardingTime,
            arrivalTime: SelectedStopTime(
                time: time.addingTimeInterval(300), source: .prediction,
                event: .departure
            )
        )
        let actualArrivalLeg = JourneyLegTiming(
            resolvedLegId: leg.id, tripId: "trip", routeId: leg.mbtaRouteId,
            directionId: leg.mbtaDirectionId,
            originStopId: leg.startStop.mbtaStopId,
            destinationStopId: leg.endStop.mbtaStopId,
            boardingTime: boardingTime,
            arrivalTime: SelectedStopTime(
                time: time.addingTimeInterval(300), source: .prediction,
                event: .arrival
            )
        )

        #expect(UpcomingArrivalNoticeDetails(legTiming: fallbackLeg, connectionTiming: nil, legs: [leg])?.arrival == nil)
        #expect(UpcomingArrivalNoticeDetails(legTiming: actualArrivalLeg, connectionTiming: nil, legs: [leg])?.arrival == actualArrivalLeg.arrival)
    }

    @Test func timingSnapshotRoundTripsSelectedStopTimes() throws {
        var state = JourneyState(route: makeRoute())
        let boardingTime = SelectedStopTime(
            time: Date(timeIntervalSince1970: 60_000),
            source: .prediction,
            event: .arrival
        )
        let arrivalTime = SelectedStopTime(
            time: Date(timeIntervalSince1970: 65_000),
            source: .schedule,
            event: .departure
        )
        state.timingState.timing = JourneyTimingPlan(
            status: .current, selectedItinerary: nil,
            currentLeg: JourneyLegTiming(
                resolvedLegId: state.legOrder[0].id,
                tripId: "trip", routeId: "route", directionId: 0,
                originStopId: "boarding", destinationStopId: "final",
                boardingTime: boardingTime, arrivalTime: arrivalTime
            ),
            recommendedDeparture: RecommendedDeparture(
                resolvedLegId: state.legOrder[0].id,
                tripId: "trip",
                boardingTime: boardingTime
            ),
            monitoredConnection: nil
        )

        let encoded = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(JourneyState.self, from: encoded)

        #expect(restored.timingState.timing?.recommendedDeparture?.boardingTime == boardingTime)
        #expect(restored.timingState.timing?.currentLegArrival == arrivalTime)
    }

    @Test func currentLegArrivalIsNilWithoutCurrentLegTiming() {
        let emptyPlan = JourneyTimingPlan(
            status: .unavailable, selectedItinerary: nil, currentLeg: nil,
            recommendedDeparture: nil, monitoredConnection: nil
        )

        #expect(emptyPlan.currentLegArrival == nil)
    }

    @Test func malformedTimingSnapshotStillThrows() throws {
        let encoded = try JSONEncoder().encode(JourneyState(route: makeRoute()))
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var timingJSON = try #require(json["timingState"] as? [String: Any])
        timingJSON["generation"] = "not a number"
        json["timingState"] = timingJSON
        let malformed = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JourneyState.self, from: malformed)
        }
    }

    @Test func timingUpdateHydratesExistingPredictionState() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let boardingStop = try #require(state.currentStop)
        let prediction = makePrediction(
            stopId: boardingStop.mbtaStopId,
            vehicleId: "vehicle-1",
            tripId: "trip-1"
        )
        let sessionId = UUID()

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: sessionId,
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: boardingStop.id,
                            displayPredictions: [prediction],
                            livePredictions: [prediction]
                        )
                    ]
                )
            )
        )

        #expect(state.timingState.refreshSessionId == sessionId)
        #expect(state.timingState.generation == 1)
        #expect(
            state.activeLegPrediction?.loadingState
                == .loaded(stopId: boardingStop.mbtaStopId, times: ["3 min"])
        )
        #expect(state.trackedVehicleId == "vehicle-1")
        #expect(state.trackedTripId == "trip-1")
        #expect(
            effects == [
                .updateTrackedVehicle(
                    vehicleId: "vehicle-1",
                    tripId: "trip-1"
                )
            ]
        )
    }

    @Test func emptySliceMarksBoardUnavailableAndPreservesArrivalDetection() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let boardingStop = try #require(state.currentStop)
        let disappearingPrediction = makePrediction(
            display: "Arriving",
            stopId: boardingStop.mbtaStopId,
            vehicleId: "vehicle-arrived",
            tripId: "trip-arrived"
        )
        state.activeLegPrediction?.lastObservedPredictions = [
            disappearingPrediction
        ]

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: UUID(),
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: boardingStop.id,
                            displayPredictions: [],
                            livePredictions: []
                        )
                    ]
                )
            )
        )

        #expect(
            state.activeLegPrediction?.loadingState
                == .unavailable(
                    stopId: boardingStop.mbtaStopId,
                    message: "No times available"
                )
        )
        #expect(
            state.activeLegPrediction?.arrivedTrains.map(\.tripId)
                == ["trip-arrived"]
        )
        #expect(state.trackedVehicleId == "vehicle-arrived")
        #expect(
            effects.contains(
                .updateTrackedVehicle(
                    vehicleId: "vehicle-arrived",
                    tripId: "trip-arrived"
                )
            )
        )
    }

    @Test func scheduleFillDoesNotHideDisappearingLiveTrain() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let boardingStop = try #require(state.currentStop)
        let oldLive = makePrediction(
            display: "Arriving",
            stopId: boardingStop.mbtaStopId,
            vehicleId: "vehicle-arrived",
            tripId: "trip-arrived"
        )
        let scheduleFill = makePrediction(
            display: "1:23 PM",
            stopId: boardingStop.mbtaStopId,
            vehicleId: "vehicle-arrived",
            tripId: "trip-arrived"
        )
        state.activeLegPrediction?.lastObservedPredictions = [oldLive]

        _ = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: UUID(),
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: boardingStop.id,
                            displayPredictions: [scheduleFill],
                            livePredictions: []
                        )
                    ]
                )
            )
        )

        #expect(state.activeLegPrediction?.arrivedTrains.map(\.tripId) == ["trip-arrived"])
        #expect(state.activeLegPrediction?.lastObservedPredictions == [scheduleFill])
        #expect(
            state.activeLegPrediction?.loadingState
                == .loaded(stopId: boardingStop.mbtaStopId, times: ["1:23 PM"])
        )
    }

    @Test func liveTrainOutsideThreeDisplaySlotsIsNotMarkedArrived() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let boardingStop = try #require(state.currentStop)
        let oldLive = makePrediction(
            display: "Arriving",
            stopId: boardingStop.mbtaStopId,
            vehicleId: "vehicle-4",
            tripId: "trip-4"
        )
        state.activeLegPrediction?.lastObservedPredictions = [oldLive]
        let firstThree = (1...3).map { index in
            makePrediction(
                stopId: boardingStop.mbtaStopId,
                vehicleId: "vehicle-\(index)",
                tripId: "trip-\(index)"
            )
        }

        _ = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: UUID(),
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: boardingStop.id,
                            displayPredictions: firstThree,
                            livePredictions: firstThree + [oldLive]
                        )
                    ]
                )
            )
        )

        #expect(state.activeLegPrediction?.arrivedTrains.isEmpty == true)
    }

    @Test func onboardRefreshDoesNotDependOnPredictionBoards() throws {
        var state = JourneyState(route: makeRoute())
        state.stopIndex = 1
        state.movementStatus = .enRoute
        state.activeLegPrediction = nil
        state.transferLegPrediction = nil
        let currentStop = try #require(state.currentStop)

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .refreshTimes(
                stopId: currentStop.mbtaStopId,
                isUserInitiated: false
            )
        )

        #expect(effects == [.updateJourneyTiming])
    }

    @Test func transferSliceHydratesWithoutChangingTrackedVehicle() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let transferTarget = state.route.legs[0].endStop
        state.activeLegPrediction = nil
        state.transferLegPrediction = PredictionState(
            predictedStop: transferTarget,
            predictedStopType: .transfer,
            acceptableRouteIds: ["route"],
            loadingState: .loading(stopId: transferTarget.mbtaStopId)
        )

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: UUID(),
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: transferTarget.id,
                            displayPredictions: [
                                makePrediction(
                                    stopId: transferTarget.mbtaStopId,
                                    vehicleId: "transfer-vehicle",
                                    tripId: "transfer-trip"
                                )
                            ],
                            livePredictions: [
                                makePrediction(
                                    stopId: transferTarget.mbtaStopId,
                                    vehicleId: "transfer-vehicle",
                                    tripId: "transfer-trip"
                                )
                            ]
                        )
                    ]
                )
            )
        )

        #expect(
            state.transferLegPrediction?.loadingState
                == .loaded(
                    stopId: transferTarget.mbtaStopId,
                    times: ["3 min"]
                )
        )
        #expect(state.trackedVehicleId == nil)
        #expect(state.trackedTripId == nil)
        #expect(effects.isEmpty)
    }

    @Test func newRefreshSessionCanReplacePersistedGeneration() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        state.timingState.refreshSessionId = UUID()
        state.timingState.generation = 100
        let newSessionId = UUID()

        _ = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: newSessionId,
                    generation: 1
                )
            )
        )

        #expect(state.timingState.refreshSessionId == newSessionId)
        #expect(state.timingState.generation == 1)
    }

    @Test func sameSessionRejectsStaleGeneration() throws {
        var state = JourneyState(route: makeRoute())
        let context = try #require(state.timingContext)
        let sessionId = UUID()
        state.timingState.refreshSessionId = sessionId
        state.timingState.generation = 10
        let originalState = state

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: sessionId,
                    generation: 9
                )
            )
        )

        #expect(state == originalState)
        #expect(effects.isEmpty)
    }

    @Test func additionalPredictionTargetDoesNotTakeVehicleSearchOwnership() async throws {
        var state = JourneyState(route: makeRoute())
        state.stopIndex = 1
        state.movementStatus = .enRoute
        state.activeLegPrediction = nil
        state.transferLegPrediction = nil
        state.trackedVehicleId = nil
        state.trackedTripId = nil
        let currentStop = try #require(state.currentStop)
        let context = try #require(state.timingContext)

        let queryPlan = await JourneyTimingEngine.shared.makeQueryPlan(
            route: state.route,
            remainingLegs: state.route.legs,
            additionalPredictionStopIds: [currentStop.id]
        )
        #expect(
            queryPlan.predictionTargets.contains(where: {
                $0.id == currentStop.id
            })
        )

        let timingEffects = JourneyCommandValidator.reduce(
            state: &state,
            command: .journeyTimingUpdate(
                update: makeUpdate(
                    routeId: state.route.id,
                    context: context,
                    sessionId: UUID(),
                    generation: 1,
                    slices: [
                        PredictionSlice(
                            predictedStopId: currentStop.id,
                            displayPredictions: [
                                makePrediction(
                                    stopId: currentStop.mbtaStopId,
                                    vehicleId: "recovered-vehicle",
                                    tripId: "recovered-trip"
                                )
                            ],
                            livePredictions: [
                                makePrediction(
                                    stopId: currentStop.mbtaStopId,
                                    vehicleId: "recovered-vehicle",
                                    tripId: "recovered-trip"
                                )
                            ]
                        )
                    ]
                )
            )
        )

        #expect(state.trackedVehicleId == nil)
        #expect(state.trackedTripId == nil)
        #expect(timingEffects.isEmpty)

        let vehicleSearchEffects = JourneyCommandValidator.reduce(
            state: &state,
            command: .vehicleSearchResult(
                vehicleId: "recovered-vehicle",
                tripId: "recovered-trip"
            )
        )

        #expect(state.trackedVehicleId == "recovered-vehicle")
        #expect(state.trackedTripId == "recovered-trip")
        #expect(
            vehicleSearchEffects == [
                .updateTrackedVehicle(
                    vehicleId: "recovered-vehicle",
                    tripId: "recovered-trip"
                ),
                .refreshTripPath(tripId: "recovered-trip")
            ]
        )
    }

    @Test func surfaceDepartureStartsVehicleSearchBeforeTimingRefresh() throws {
        var state = JourneyState(route: makeRoute())
        state.movementStatus = .atStop
        state.trackedVehicleId = nil
        state.trackedTripId = nil
        let boardingStop = try #require(state.currentStop)

        let effects = JourneyCommandValidator.reduce(
            state: &state,
            command: .executeExit(stopId: boardingStop.mbtaStopId)
        )

        #expect(effects.first == .searchForVehicle)
        #expect(effects.contains(.updateJourneyTiming))
    }

    private func makeUpdate(
        routeId: UUID,
        context: JourneyTimingContext,
        sessionId: UUID,
        generation: UInt64,
        slices: [PredictionSlice] = []
    ) -> JourneyTimingUpdate {
        JourneyTimingUpdate(
            resolvedRouteId: routeId,
            context: context,
            refreshSessionId: sessionId,
            generation: generation,
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            predictionSlices: slices,
            timing: JourneyTimingPlan(
                status: .current,
                selectedItinerary: nil,
                currentLeg: nil,
                recommendedDeparture: nil,
                monitoredConnection: nil
            )
        )
    }

    private func makePrediction(
        display: String = "3 min",
        stopId: String,
        vehicleId: String,
        tripId: String
    ) -> TransitPrediction {
        TransitPrediction(
            display: display,
            arrivalDate: Date(timeIntervalSince1970: 1_180),
            departureDate: Date(timeIntervalSince1970: 1_200),
            vehicleId: vehicleId,
            predictionId: "prediction-\(tripId)",
            tripId: tripId,
            stopId: stopId,
            routeId: "route",
            headsign: "Destination",
            directionId: 0,
            stopSequence: 1
        )
    }

    private func makeRoute() -> ResolvedUserRoute {
        let sourceLegId = UUID()
        let resolvedLegId = UUID()
        let boarding = makeStop(
            sourceLegId: sourceLegId,
            legIndex: 0,
            legStopIndex: 0,
            stopId: "boarding",
            role: .boarding
        )
        let intermediate = makeStop(
            sourceLegId: sourceLegId,
            legIndex: 0,
            legStopIndex: 1,
            stopId: "intermediate",
            role: .intermediate
        )
        let final = makeStop(
            sourceLegId: sourceLegId,
            legIndex: 0,
            legStopIndex: 2,
            stopId: "final",
            role: .final
        )
        let leg = ResolvedLeg(
            id: resolvedLegId,
            sourceLegId: sourceLegId,
            legIndex: 0,
            startStop: boarding,
            endStop: final,
            mbtaRouteId: "route",
            mbtaDirectionId: 0,
            transitType: .bus,
            selectedPatternId: "pattern",
            acceptableRouteIds: ["route"],
            stops: [boarding, intermediate, final],
            patternStops: []
        )
        return ResolvedUserRoute(
            legs: [leg],
            id: UUID(),
            name: "Test Route",
            timeStamp: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeStop(
        sourceLegId: UUID,
        legIndex: Int,
        legStopIndex: Int,
        stopId: String,
        role: JourneyStopRole
    ) -> ResolvedStop {
        ResolvedStop(
            sourceLegId: sourceLegId,
            legIndex: legIndex,
            legStopIndex: legStopIndex,
            patternStopIndex: legStopIndex,
            patternEdgeSequenceNumber: legStopIndex,
            platformId: stopId,
            stationId: "station-\(stopId)",
            mbtaStopId: stopId,
            mbtaRouteId: "route",
            mbtaDirectionId: 0,
            stopName: stopId.capitalized,
            longitude: -71,
            latitude: 42,
            address: "",
            acceptableStopIds: [stopId],
            journeyRole: role,
            monitoringMode: .surface,
            transitType: .bus
        )
    }
}

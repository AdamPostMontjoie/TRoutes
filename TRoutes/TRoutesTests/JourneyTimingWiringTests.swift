//
//  JourneyTimingWiringTests.swift
//  TRoutesTests
//

import Foundation
import Testing
@testable import TRoutes

struct JourneyTimingWiringTests {
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
            status: .current,
            predictionSlices: slices,
            recommendedDeparture: nil,
            currentLegArrival: nil,
            destinationArrival: nil,
            connection: nil
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

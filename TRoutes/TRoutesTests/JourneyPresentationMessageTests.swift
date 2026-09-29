import Foundation
import Testing
@testable import TRoutes

struct JourneyPresentationMessageTests {
    private let departure = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func ordinaryTightConnectionStaysSilent() {
        #expect(message(for: .none) == nil)
        #expect(message(for: .tight) == nil)
    }

    @Test func shortETAsUseMinutesAndCurrentLegHasItsOwnLabel() {
        let now = departure
        let soon = now.addingTimeInterval(24 * 60)
        let later = now.addingTimeInterval(60 * 60)

        #expect(JourneyPresentationState.etaText(soon, relativeTo: now) == "Arrive in 24 min")
        #expect(JourneyPresentationState.etaText(soon, relativeTo: now, isCurrentLeg: true) == "Leg: 24 min")
        #expect(JourneyPresentationState.etaText(later, relativeTo: now).hasPrefix("Arrive "))
        #expect(!JourneyPresentationState.etaText(later, relativeTo: now).contains(" min"))
    }

    @Test func consequenceAndFeasibilityHaveDifferentActions() throws {
        let consequence = try #require(message(for: .highConsequence, isLastService: true))
        #expect(consequence.detail.contains("last service"))
        #expect(consequence.nextAction == nil)

        let tightConsequence = try #require(message(for: .tightHighConsequence))
        #expect(tightConsequence.nextAction?.contains("Hurry") == true)

        let replacement = departure.addingTimeInterval(20 * 60)
        let changed = try #require(message(for: .likelyMiss, replacementDeparture: replacement))
        #expect(changed.title == "Your connection has changed")
        #expect(changed.detail.contains("Take the"))
        #expect(changed.nextAction?.contains("instead") == true)
        #expect(!changed.detail.contains("Hurry"))

        let unresolved = try #require(message(for: .likelyMiss))
        #expect(unresolved.title == "Checking your next connection")
        #expect(unresolved.detail.contains("new journey ETA isn’t available"))
    }

    @Test(arguments: [ConnectionWarning.none, .tight])
    func safeSelectedJourneyDoesNotWarnAboutEarlierMissedTrain(warning: ConnectionWarning) {
        let journey = makeJourney(selectedWarning: warning)

        #expect(journey.timingState.timing?.monitoredConnection?.warning == .likelyMiss)
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)
    }

    @Test(arguments: [ConnectionWarning.highConsequence, .tightHighConsequence])
    func bannerDescribesSelectedConnection(warning: ConnectionWarning) throws {
        let journey = makeJourney(selectedWarning: warning)
        let banner = try #require(JourneyPresentationState(journey: journey).timingWarning)

        #expect(banner.title == (warning == .highConsequence ? "Don’t miss this connection" : "Move quickly for RL"))
        #expect(!banner.detail.contains("instead"))
        #expect(!banner.detail.contains("too little time"))
    }

    @Test(arguments: [false, true])
    func warningEndsAtTransferArrivalBeforeTimingRefresh(overlapsNext: Bool) throws {
        var journey = makeJourney(selectedWarning: .tightHighConsequence, overlapsNext: overlapsNext)
        journey.stopIndex = 2
        let retainedTiming = journey.timingState.timing
        #expect(JourneyPresentationState(journey: journey).timingWarning != nil)

        _ = JourneyAction.arriveAtStop.reduce(state: &journey)

        #expect(journey.timingContext?.timingLegId == journey.legOrder[1].id)
        #expect(journey.timingState.timing == retainedTiming)
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)
    }

    @Test func departingIntermediateStopPreservesWarningForUpcomingTransfer() {
        var journey = makeJourney(selectedWarning: .tightHighConsequence)
        journey.movementStatus = .atStop

        _ = JourneyAction.departFromStop.reduce(state: &journey)

        #expect(journey.timingContext?.timingLegId == journey.legOrder[0].id)
        #expect(JourneyPresentationState(journey: journey).timingWarning?.title == "Move quickly for RL")
    }

    @Test func onboardWarningRequiresMatchingTrackedTrip() {
        var journey = makeJourney(selectedWarning: .tightHighConsequence)
        journey.trackedTripId = "other-trip"
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)

        journey.trackedTripId = nil
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)
    }

    @Test func noWarningBeforeInitialArrivalOrAtDestination() {
        var journey = makeJourney(selectedWarning: .tightHighConsequence)
        journey.stopIndex = 0
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)

        journey.stopIndex = journey.stopOrder.count - 1
        journey.legIndex = 1
        _ = JourneyAction.arriveAtStop.reduce(state: &journey)
        #expect(journey.timingContext == nil)
        #expect(JourneyPresentationState(journey: journey).timingWarning == nil)
    }

    @Test(arguments: [false, true])
    func noFeasibleJourneyOnlyWarnsForHighConsequenceMiss(highConsequence: Bool) throws {
        var journey = makeJourney(selectedWarning: nil)
        let original = try #require(journey.timingState.timing)
        journey.timingState.timing = JourneyTimingPlan(
            status: .unavailable,
            selectedItinerary: nil,
            currentLeg: original.currentLeg,
            recommendedDeparture: nil,
            monitoredConnection: makeConnection(in: journey, warning: .likelyMiss, highConsequence: highConsequence)
        )

        let banner = JourneyPresentationState(journey: journey).timingWarning
        #expect(banner?.title == (highConsequence ? "Connection at risk" : nil))
        #expect(banner?.nextAction == nil)
        #expect(banner?.detail.contains("Checking") != true)
    }

    @Test func liveActivityETAHasOnlyMinutesOrClockTime() throws {
        let now = departure
        #expect(JourneyAttributes.etaText(now.addingTimeInterval(47 * 60), relativeTo: now) == "47m")
        #expect(JourneyAttributes.etaText(now.addingTimeInterval(3599), relativeTo: now) == "60m")
        #expect(JourneyAttributes.etaText(now, relativeTo: now) == "0m")
        #expect(JourneyAttributes.etaText(now.addingTimeInterval(-60), relativeTo: now) == "0m")

        let noon = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12, minute: 2)))
        #expect(JourneyAttributes.etaText(noon, relativeTo: noon.addingTimeInterval(-3600)) == "12:02")
    }

    private func makeJourney(selectedWarning: ConnectionWarning?, overlapsNext: Bool = false) -> JourneyState {
        let feederId = UUID()
        let connectingId = UUID()
        let boarding = makeStop(legId: feederId, legIndex: 0, index: 0, role: .boarding)
        let intermediate = makeStop(legId: feederId, legIndex: 0, index: 1, role: .intermediate)
        let transfer = makeStop(legId: feederId, legIndex: 0, index: 2, role: .transfer(overlapsNext: overlapsNext))
        let nextBoarding = makeStop(legId: connectingId, legIndex: 1, index: 0, role: .boarding)
        let destination = makeStop(legId: connectingId, legIndex: 1, index: 1, role: .final)
        let feeder = ResolvedLeg(
            id: feederId, sourceLegId: feederId, legIndex: 0,
            startStop: boarding, endStop: transfer,
            mbtaRouteId: "Orange", mbtaDirectionId: 0, transitType: .orangeLine,
            selectedPatternId: "feeder", stops: [boarding, intermediate, transfer], patternStops: []
        )
        let connecting = ResolvedLeg(
            id: connectingId, sourceLegId: connectingId, legIndex: 1,
            startStop: nextBoarding, endStop: destination,
            mbtaRouteId: "Red", mbtaDirectionId: 0, transitType: .redLine,
            selectedPatternId: "connecting", stops: [nextBoarding, destination], patternStops: []
        )
        var journey = JourneyState(route: ResolvedUserRoute(
            legs: [feeder, connecting], id: UUID(), name: "Test", timeStamp: departure
        ))
        journey.stopIndex = 1
        journey.trackedTripId = "feeder"
        let currentLeg = makeTimedLeg(feeder, tripId: "feeder", boarding: departure.addingTimeInterval(-600), arrival: departure)
        let selectedConnection = selectedWarning.map {
            makeConnection(in: journey, warning: $0, highConsequence: $0 == .highConsequence || $0 == .tightHighConsequence)
        }
        let selected = selectedConnection.map { connection in
            JourneyTimingItinerary(
                legs: [currentLeg, makeTimedLeg(connecting, tripId: connection.departingTripId, boarding: connection.departure, arrival: connection.departure.addingTimeInterval(900))],
                connections: [connection]
            )
        }
        journey.timingState.timing = JourneyTimingPlan(
            status: selected == nil ? .unavailable : .current,
            selectedItinerary: selected, currentLeg: currentLeg, recommendedDeparture: nil,
            monitoredConnection: makeConnection(in: journey, warning: .likelyMiss, highConsequence: true)
        )
        return journey
    }

    private func makeConnection(in journey: JourneyState, warning: ConnectionWarning, highConsequence: Bool) -> JourneyConnectionTiming {
        let gap: TimeInterval = warning == .likelyMiss ? 30 : (warning == .tight || warning == .tightHighConsequence ? 90 : 600)
        return JourneyConnectionTiming(
            arrivingLegId: journey.legOrder[0].id, arrivingTripId: "feeder",
            departingLegId: journey.legOrder[1].id, departingTripId: warning == .likelyMiss ? "earlier" : "selected",
            stationId: "transfer", arrivingStopId: "arrival", departingStopId: "boarding",
            arrival: departure, arrivingTimingSource: .prediction,
            boardingTime: SelectedStopTime(time: departure.addingTimeInterval(gap), source: .prediction, event: .arrival),
            minimumTransferDuration: 60, preferredReliabilityBuffer: 120,
            nextAlternativeDeparture: departure.addingTimeInterval(highConsequence ? 75 * 60 : 20 * 60),
            isHighConsequence: highConsequence, isLastService: false, warning: warning
        )
    }

    private func makeTimedLeg(_ leg: ResolvedLeg, tripId: String, boarding: Date, arrival: Date) -> JourneyLegTiming {
        JourneyLegTiming(
            resolvedLegId: leg.id, tripId: tripId, routeId: leg.mbtaRouteId, directionId: 0,
            originStopId: leg.startStop.mbtaStopId, destinationStopId: leg.endStop.mbtaStopId,
            boardingTime: SelectedStopTime(time: boarding, source: .prediction, event: .arrival),
            arrivalTime: SelectedStopTime(time: arrival, source: .prediction, event: .arrival)
        )
    }

    private func makeStop(legId: UUID, legIndex: Int, index: Int, role: JourneyStopRole) -> ResolvedStop {
        let id = "\(legIndex)-\(index)"
        return ResolvedStop(
            sourceLegId: legId, legIndex: legIndex, legStopIndex: index,
            patternStopIndex: index, patternEdgeSequenceNumber: index,
            platformId: id, stationId: id, mbtaStopId: id, mbtaRouteId: legIndex == 0 ? "Orange" : "Red", mbtaDirectionId: 0,
            stopName: "Stop \(id)", longitude: -71, latitude: 42, address: "",
            acceptableStopIds: [id], journeyRole: role, monitoringMode: .underground, transitType: .heavyRail
        )
    }

    private func message(
        for warning: ConnectionWarning,
        isLastService: Bool = false,
        replacementDeparture: Date? = nil
    ) -> JourneyPresentationState.TimingMessage? {
        JourneyPresentationState.warningMessage(
            warning: warning,
            routeName: "Red Line",
            stopName: "Downtown Crossing",
            boardingTime: departure,
            availableTime: 90,
            nextAlternativeDeparture: nil,
            isLastService: isLastService,
            replacementDeparture: replacementDeparture,
            replacementArrival: replacementDeparture?.addingTimeInterval(15 * 60)
        )
    }
}

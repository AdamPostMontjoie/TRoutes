//
//  JourneyTimingConnectionTests.swift
//  TRoutesTests
//

import Foundation
import Testing
@testable import TRoutes

struct JourneyTimingConnectionTests {
    @Test func safeLowConsequenceConnectionHasNoWarning() {
        let connection = makeConnection(
            departureMinutesAfterArrival: 8,
            isHighConsequence: false
        )

        #expect(connection.isPhysicallyPossible)
        #expect(connection.meetsReliabilityBuffer)
        #expect(connection.warning == .none)
    }

    @Test func tightLowConsequenceConnectionWarns() {
        let connection = makeConnection(
            departureMinutesAfterArrival: 7,
            isHighConsequence: false
        )

        #expect(connection.isPhysicallyPossible)
        #expect(!connection.meetsReliabilityBuffer)
        #expect(connection.warning == .tight)
    }

    @Test func safeHighConsequenceConnectionWarns() {
        let connection = makeConnection(
            departureMinutesAfterArrival: 8,
            isHighConsequence: true
        )

        #expect(connection.isPhysicallyPossible)
        #expect(connection.meetsReliabilityBuffer)
        #expect(connection.warning == .highConsequence)
    }

    @Test func tightHighConsequenceConnectionCombinesBothWarnings() {
        let connection = makeConnection(
            departureMinutesAfterArrival: 7,
            isHighConsequence: true
        )

        #expect(connection.isPhysicallyPossible)
        #expect(!connection.meetsReliabilityBuffer)
        #expect(connection.warning == .tightHighConsequence)
    }

    @Test func exactPhysicalBoundaryIsLikelyMiss() {
        let connection = makeConnection(
            departureMinutesAfterArrival: 3,
            isHighConsequence: true
        )

        #expect(!connection.isPhysicallyPossible)
        #expect(connection.warning == .likelyMiss)
    }

    @Test func consequenceDoesNotChangePhysicalFeasibility() {
        let ordinary = makeConnection(
            departureMinutesAfterArrival: 7,
            isHighConsequence: false
        )
        let consequential = makeConnection(
            departureMinutesAfterArrival: 7,
            isHighConsequence: true
        )

        #expect(ordinary.isPhysicallyPossible == consequential.isPhysicallyPossible)
        #expect(ordinary.physicalSlack == consequential.physicalSlack)
        #expect(ordinary.bufferSlack == consequential.bufferSlack)
    }

    private func makeConnection(
        departureMinutesAfterArrival: TimeInterval,
        isHighConsequence: Bool
    ) -> TransferTiming {
        let arrival = Date(timeIntervalSince1970: 1_000)
        return TransferTiming(
            arrivingLegId: UUID(),
            departingLegId: UUID(),
            stationId: "transfer-station",
            arrival: arrival,
            departure: arrival.addingTimeInterval(
                departureMinutesAfterArrival * 60
            ),
            requirement: TransferRequirement(
                minimumTransferTime: 3 * 60,
                preferredReliabilityBuffer: 5 * 60
            ),
            nextAlternativeDeparture: isHighConsequence
                ? arrival.addingTimeInterval(2 * 60 * 60)
                : arrival.addingTimeInterval(20 * 60),
            isHighConsequence: isHighConsequence,
            isLastService: false
        )
    }
}

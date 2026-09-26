//
//  JourneyTimingPlan.swift
//  TRoutes
//

import Foundation

enum JourneyTimingStatus: String, Codable, Sendable {
    case idle
    case loading
    case current
    case stale
    case unavailable
}

/// The departure JourneyTimingEngine recommends before initial boarding.
struct RecommendedDeparture: Equatable, Codable, Sendable {
    let resolvedLegId: UUID
    let tripId: String
    let departureTime: Date
    let timeSource: TimingSource
    let boardingEvent: TimingEvent
}

/// The user-facing warning for a connection opportunity.
enum ConnectionWarning: String, Equatable, Codable, Sendable {
    case none
    case tight
    case highConsequence
    case tightHighConsequence
    case likelyMiss

    var notificationUrgency: Int {
        switch self {
        case .none:
            return 0
        case .tight, .highConsequence:
            return 1
        case .tightHighConsequence:
            return 2
        case .likelyMiss:
            return 3
        }
    }
}

/// One selected trip between a resolved leg's endpoints.
struct JourneyLegTiming: Equatable, Codable, Sendable, Identifiable {
    let resolvedLegId: UUID
    let tripId: String
    let routeId: String
    let directionId: Int
    let originStopId: String
    let destinationStopId: String
    let departure: Date //When we depart startstop on leg
    let arrival: Date //When we arrive at endstop on leg
    let departureTimingSource: TimingSource
    let arrivalTimingSource: TimingSource

    var id: UUID {
        resolvedLegId
    }
}

/// Timing, reliability, and consequence facts for one connection opportunity.
struct JourneyConnectionTiming: Equatable, Codable, Sendable {
    let arrivingLegId: UUID
    let arrivingTripId: String
    let departingLegId: UUID
    let departingTripId: String
    let stationId: String
    let arrivingStopId: String
    let departingStopId: String
    let arrival: Date
    let arrivingTimingSource: TimingSource
    let departure: Date
    let departingTimingSource:TimingSource
    let boardingEvent: TimingEvent
    let minimumTransferDuration: TimeInterval
    let preferredReliabilityBuffer: TimeInterval
    let nextAlternativeDeparture: Date?
    let isHighConsequence: Bool
    let isLastService: Bool
    let warning: ConnectionWarning

    var physicalSlack: TimeInterval {
        departure.timeIntervalSince(arrival) - minimumTransferDuration
    }

    var bufferSlack: TimeInterval {
        physicalSlack - preferredReliabilityBuffer
    }

    var platformWaitDuration: TimeInterval {
        max(0, physicalSlack)
    }

    var isPhysicallyPossible: Bool {
        physicalSlack > 0
    }

    func isSameConnection(as other: JourneyConnectionTiming) -> Bool {
        arrivingLegId == other.arrivingLegId
            && arrivingTripId == other.arrivingTripId
            && departingLegId == other.departingLegId
            && departingTripId == other.departingTripId
    }
}

/// The complete feasible path currently producing the displayed ETA.
struct JourneyTimingItinerary: Equatable, Codable, Sendable {
    let legs: [JourneyLegTiming]
    let connections: [JourneyConnectionTiming]
    
    var destinationArrival: Date? {
        legs.last?.arrival
    }
}

/// One route-wide timing result accepted and presented as a unit.
struct JourneyTimingPlan: Equatable, Codable, Sendable {
    let status: JourneyTimingStatus
    let selectedItinerary: JourneyTimingItinerary?

    /// The leg currently producing the leg ETA after initial boarding. It can
    /// remain available when no complete feasible itinerary exists.
    let currentLeg: JourneyLegTiming?
    let recommendedDeparture: RecommendedDeparture?
    
    /// The immediate connection being monitored.
    let monitoredConnection: JourneyConnectionTiming?

    //when will this leg get to the end?
    var currentLegArrival: NoticeTime? {
        NoticeTime(time: currentLeg?.arrival, source: currentLeg?.arrivalTimingSource)
    }
    //when will the intended transfer depart the stop we board?
    var nextLegDeparture: NoticeTime? {
        guard let monitoredConnection else { return nil }
        let selectedLeg = selectedItinerary?.legs.first {
            $0.resolvedLegId == monitoredConnection.departingLegId
        }
        return NoticeTime(
            time: selectedLeg?.departure ?? monitoredConnection.departure,
            source: selectedLeg?.departureTimingSource ?? monitoredConnection.departingTimingSource
        )
    }
    var connectionWarning: ConnectionWarning? {
        monitoredConnection?.warning
    }

    var destinationArrival: Date? {
        selectedItinerary?.destinationArrival
    }
}

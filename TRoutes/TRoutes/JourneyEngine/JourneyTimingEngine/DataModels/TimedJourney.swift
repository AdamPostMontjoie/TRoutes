//
//  TimedJourney.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

enum TimingConfidence: String, Codable, Sendable {
    case predicted
    case mixed
    case scheduled
}

/// One usable same-trip option for traveling from a leg's origin to destination.
/// The solver constructs this only after both endpoint calls have been matched.
struct LegTripOption: Equatable, Sendable, Identifiable {
    let legId: UUID
    let origin: StopCall
    let destination: StopCall
    let departure: Date
    let arrival: Date
    let departureTimeSource: TimingSource
    let confidence: TimingConfidence

    /// Rejects mismatched stop calls here so later journey solving can assume
    /// that every option is one forward-moving ride on a single service.
    init?(
        legId: UUID,
        origin: StopCall,
        destination: StopCall
    ) {
        guard origin.key.tripId == destination.key.tripId,
              origin.routeId == destination.routeId,
              origin.directionId == destination.directionId,
              let departure = origin.effectiveDeparture,
              let departureTimeSource = origin.effectiveDepartureSource,
              let arrival = destination.effectiveArrival,
              arrival >= departure else {
            return nil
        }

        self.legId = legId
        self.origin = origin
        self.destination = destination
        self.departure = departure
        self.arrival = arrival
        self.departureTimeSource = departureTimeSource

        switch (origin.availability, destination.availability) {
        case (.predicted, .predicted):
            confidence = .predicted
        case (.scheduledOnly, .scheduledOnly):
            confidence = .scheduled
        default:
            confidence = .mixed
        }
    }

    var tripId: String {
        origin.key.tripId
    }

    var routeId: String {
        origin.routeId
    }

    var id: String {
        "\(legId)-\(tripId)"
    }

    var duration: TimeInterval {
        arrival.timeIntervalSince(departure)
    }
}

/// The time required to make a transfer. Physical movement and risk protection
/// are separate so product policy can tune them independently.
struct TransferRequirement: Equatable, Sendable {
    let minimumTransferTime: TimeInterval
    let safetyMargin: TimeInterval
    var requiredTime: TimeInterval {
        minimumTransferTime + safetyMargin
    }
}

enum ConnectionRisk: String, Sendable {
    case normal
    case tight
    case highConsequence
    case lastService
}

struct TransferTiming: Equatable, Sendable {
    let arrivingLegId: UUID
    let departingLegId: UUID
    let stationId: String
    let arrival: Date
    let departure: Date
    let requirement: TransferRequirement
    let nextAlternativeDeparture: Date?
    let risk: ConnectionRisk

    var usableSlack: TimeInterval {
        departure.timeIntervalSince(arrival) - requirement.requiredTime
    }
}

enum TimingWarning: Equatable, Codable, Sendable {
    case tightConnection(stationId: String)
    case longRecoveryGap(stationId: String, seconds: TimeInterval)
    case lastService(stationId: String)
    case scheduleOnly(legId: UUID)
    case predictionTemporarilyUnavailable(legId: UUID)
    case incompleteCoverage(legId: UUID)
}

/// A complete feasible choice of trips through the remaining route.
struct TimedJourney: Equatable, Sendable {
    let legs: [LegTripOption]
    let transfers: [TransferTiming]
    let warnings: [TimingWarning]

    /// A timed journey is a non-empty, ordered set of legs with exactly one
    /// feasible transfer joining every adjacent pair.
    init?(
        legs: [LegTripOption],
        transfers: [TransferTiming],
        warnings: [TimingWarning]
    ) {
        guard !legs.isEmpty,
              Set(legs.map(\.legId)).count == legs.count,
              transfers.count == legs.count - 1 else {
            return nil
        }

        for (index, transfer) in transfers.enumerated() {
            guard transfer.arrivingLegId == legs[index].legId,
                  transfer.departingLegId == legs[index + 1].legId,
                  transfer.arrival == legs[index].arrival,
                  transfer.departure == legs[index + 1].departure,
                  transfer.usableSlack >= 0 else {
                return nil
            }
        }

        self.legs = legs
        self.transfers = transfers
        self.warnings = warnings
    }

    var originDeparture: Date {
        legs[0].departure
    }

    var destinationArrival: Date {
        legs[legs.count - 1].arrival
    }

    var confidence: TimingConfidence {
        if legs.allSatisfy({ $0.confidence == .predicted }) {
            return .predicted
        }
        if legs.allSatisfy({ $0.confidence == .scheduled }) {
            return .scheduled
        }
        return .mixed
    }
}

enum TimingCoverageStatus: String, Sendable {
    case sufficient
    case insufficient
    case truncated
    case unavailable
}

/// Whether both endpoints contain enough complete same-trip options for a leg.
struct LegTimingCoverage: Equatable, Sendable {
    let legId: UUID
    let originCoveredThrough: Date?
    let destinationCoveredThrough: Date?
    let completeTripOptionCount: Int
    let status: TimingCoverageStatus
}

/// Internal result of one route-wide timing refresh.
struct RouteTimingSnapshot: Equatable, Sendable {
    let resolvedRouteId: UUID
    let context: JourneyTimingContext
    let generation: UInt64
    let fetchedAt: Date
    let calls: [TripStopKey: StopCall]
    let optionsByLeg: [UUID: [LegTripOption]]
    let coverageByLeg: [UUID: LegTimingCoverage]
    let recommendedJourney: TimedJourney?
}

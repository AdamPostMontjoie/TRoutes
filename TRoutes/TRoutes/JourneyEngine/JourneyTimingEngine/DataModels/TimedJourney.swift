//
//  TimedJourney.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Summarizes prediction and schedule availability at leg endpoints.
enum TimingSourceComposition: String, Codable, Sendable {
    case predicted
    case mixed
    case scheduled
}

/// A same-trip timing option between a leg's endpoints.
struct LegTripOption: Equatable, Sendable, Identifiable {
    let legId: UUID
    let origin: TripStopTiming
    let destination: TripStopTiming
    let departure: Date
    let arrival: Date
    let departureTimeSource: TimingSource
    let sourceComposition: TimingSourceComposition

    /// Rejects mismatched trip-stop timings before journey solving.
    init?(
        legId: UUID,
        origin: TripStopTiming,
        destination: TripStopTiming
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
            sourceComposition = .predicted
        case (.scheduledOnly, .scheduledOnly):
            sourceComposition = .scheduled
        default:
            sourceComposition = .mixed
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

/// Physical movement and preferred reliability protection are separate. Only
/// physical movement determines whether a connection remains possible.
struct TransferRequirement: Equatable, Codable, Sendable {
    let minimumTransferTime: TimeInterval
    let preferredReliabilityBuffer: TimeInterval
}

/// The next transfer currently being evaluated. Impossible transfers may be
/// retained here for warning purposes even though the journey solver excludes
/// them from a complete path.
struct TransferTiming: Equatable, Codable, Sendable {
    let arrivingLegId: UUID
    let departingLegId: UUID
    let stationId: String
    let arrival: Date
    let departure: Date
    let requirement: TransferRequirement
    let nextAlternativeDeparture: Date?
    let isHighConsequence: Bool
    let isLastService: Bool

    var physicalSlack: TimeInterval {
        departure.timeIntervalSince(arrival) - requirement.minimumTransferTime
    }

    var bufferSlack: TimeInterval {
        physicalSlack - requirement.preferredReliabilityBuffer
    }

    /// Reaching the platform exactly at departure is not treated as boardable.
    var isPhysicallyPossible: Bool {
        physicalSlack > 0
    }

    var meetsReliabilityBuffer: Bool {
        isPhysicallyPossible && bufferSlack >= 0
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
    init?(legs: [LegTripOption], transfers: [TransferTiming], warnings: [TimingWarning]){
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
                  transfer.isPhysicallyPossible else {
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

    var sourceComposition: TimingSourceComposition {
        if legs.allSatisfy({ $0.sourceComposition == .predicted }) {
            return .predicted
        }
        if legs.allSatisfy({ $0.sourceComposition == .scheduled }) {
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
    let timingsByTripStop: [TripStopKey: TripStopTiming]
    let optionsByLeg: [UUID: [LegTripOption]]
    let coverageByLeg: [UUID: LegTimingCoverage]
    let etaJourney: TimedJourney?
    let recommendedJourney: TimedJourney?
    let connection: TransferTiming?
}

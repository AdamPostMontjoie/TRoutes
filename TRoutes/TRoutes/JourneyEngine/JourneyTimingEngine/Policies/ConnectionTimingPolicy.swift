//
//  ConnectionTimingPolicy.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import CoreLocation
import Foundation

/// Product policy for evaluating one transfer. It converts route and timing
/// facts into a preferred buffer and consequence classification; it does not
/// decide whether a physically impossible edge belongs in a solved journey.
struct ConnectionTimingPolicy {
    // MARK: - Policy values to validate with real journey data

    private let ordinaryReliabilityBuffer: TimeInterval = 2 * 60
    private let infrequentServiceReliabilityBuffer: TimeInterval = 5 * 60
    private let longRecoveryThreshold: TimeInterval = 60 * 60
    private let assumedWalkingSpeedMetersPerSecond = 1.4

    /// This is deliberately independent of the recovery gap. Missing an
    /// infrequent service changes consequence, not physical transfer duration.
    func preferredReliabilityBuffer(
        for departingLeg: ResolvedLeg
    ) -> TimeInterval {
        switch departingLeg.transitType {
        case .commuterRail, .ferry:
            return infrequentServiceReliabilityBuffer
        default:
            return ordinaryReliabilityBuffer
        }
    }

    func transferRequirement(
        from arrivingLeg: ResolvedLeg,
        to departingLeg: ResolvedLeg
    ) -> TransferRequirement {
        let arrivalLocation = CLLocation(
            latitude: arrivingLeg.endStop.latitude,
            longitude: arrivingLeg.endStop.longitude
        )
        let departureLocation = CLLocation(
            latitude: departingLeg.startStop.latitude,
            longitude: departingLeg.startStop.longitude
        )
        let walkingDistance = arrivalLocation.distance(from: departureLocation)

        return TransferRequirement(
            minimumTransferTime: walkingDistance
                / assumedWalkingSpeedMetersPerSecond,
            preferredReliabilityBuffer: preferredReliabilityBuffer(
                for: departingLeg
            )
        )
    }

    func isHighConsequence(
        departure: Date,
        nextAlternativeDeparture: Date?,
        isLastService: Bool
    ) -> Bool {
        if isLastService {
            return true
        }
        guard let nextAlternativeDeparture else { return false }
        return nextAlternativeDeparture.timeIntervalSince(departure)
            > longRecoveryThreshold
    }
}

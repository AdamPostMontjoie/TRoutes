//
//  JourneyTimingContext.swift
//  TRoutes
//
import Foundation

/// The progression facts JourneyTimingEngine needs in order to interpret times.
/// JourneyEngine derives this from JourneyState; the timing engine never advances
/// the journey or attempts to infer whether the passenger boarded.
struct JourneyTimingContext: Equatable, Sendable {
    let timingLegId: UUID
    let phase: Phase

    enum Phase: Equatable, Sendable {
        case awaitingBoarding
        case onboard(tripId: String?)
        case transferring
    }

    var onboardTripId: String? {
        guard case let .onboard(tripId) = phase else { return nil }
        return tripId
    }

    var isOnboard: Bool {
        if case .onboard = phase {
            return true
        }
        return false
    }
}

//
//  JourneyTimingContext.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// The progression facts JourneyTimingEngine uses in order to interpret times.
struct JourneyTimingContext: Equatable, Sendable {
    let timingLegId: UUID
    let phase: Phase

    enum Phase: Equatable, Sendable {
        case approachingBoarding
        case atBoardingStop
        case onboard(tripId: String?)
        case transferring
    }

    var allowsRecommendation: Bool {
        phase == .approachingBoarding
    }

    var showsConnectionWarning: Bool {
        !allowsRecommendation
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

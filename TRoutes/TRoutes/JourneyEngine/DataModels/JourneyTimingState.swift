//
//  JourneyTimingState.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

enum JourneyTimingStatus: String, Codable, Sendable {
    case idle
    case loading
    case current
    case stale
    case unavailable
}

/// The durable facts needed to identify and present a departure recommendation.
/// Display strings are derived later by JourneyPresentationState.
struct RecommendedDeparture: Equatable, Codable, Sendable {
    let departureTime: Date
    let timeSource: TimingSource
    let destinationArrivalTime: Date
    let selectedTripIds: [String]
    let confidence: TimingConfidence

    var firstTripId: String? {
        selectedTripIds.first
    }
}

/// The user-facing classification of the next transfer on the journey's
/// currently assumed path. The connection retains the facts used to derive it.
enum ConnectionWarning: String, Equatable, Codable, Sendable {
    case none
    case tight
    case highConsequence
    case tightHighConsequence
    case likelyMiss
}

/// The small persisted timing summary owned by JourneyState. Raw API observations
/// and query plans remain inside JourneyTimingEngine. PredictionManager owns
/// the reusable schedule cache.
struct JourneyTimingState: Equatable, Codable, Sendable {
    var status: JourneyTimingStatus = .idle
    var generation: UInt64 = 0
    var updatedAt: Date?
    var recommendedDeparture: RecommendedDeparture?
    var currentLegArrival: Date?
    var destinationArrival: Date?
    var connection: TransferTiming?
}

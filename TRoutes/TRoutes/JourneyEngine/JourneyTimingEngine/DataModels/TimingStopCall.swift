//
//  TimingStopCall.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Arrival and departure remain separate because a leg boards using departure
/// time and reaches its destination using arrival time.
struct StopTimes: Equatable, Sendable {
    let arrival: Date?
    let departure: Date?
}

/// Identifies one trip's call at one stop. `stopSequence` distinguishes repeated
/// visits to the same stop when that information is available.
struct TripStopKey: Hashable, Sendable {
    let tripId: String
    let stopId: String
    let stopSequence: Int?
}

enum StopCallAvailability: String, Sendable {
    case scheduledOnly
    case predicted
    case predictionLost
    case departed
    case canceled
}

/// The merged scheduled and real-time facts for one trip at one stop.
///
/// A prediction overlays the corresponding schedule when the MBTA supplies a
/// schedule relationship. Prediction-only added service has no scheduled value.
struct StopCall: Equatable, Sendable {
    let key: TripStopKey
    let routeId: String
    let directionId: Int
    let vehicleId: String?

    let scheduleId: String?
    let predictionId: String?

    let scheduled: StopTimes?
    let predicted: StopTimes?

    let status: String?
    let scheduleRelationship: String?
    let availability: StopCallAvailability

    /// Arrival is preferred at a leg destination.
    var effectiveArrival: Date? {
        predicted?.arrival
            ?? predicted?.departure
            ?? scheduled?.arrival
            ?? scheduled?.departure
    }

    /// Departure is preferred at a leg origin.
    var effectiveDeparture: Date? {
        predicted?.departure
            ?? predicted?.arrival
            ?? scheduled?.departure
            ?? scheduled?.arrival
    }
}

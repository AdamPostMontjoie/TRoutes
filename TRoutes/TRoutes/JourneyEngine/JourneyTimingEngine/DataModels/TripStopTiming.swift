//
//  TimingStopCall.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

enum TimingSource: String, Codable, Sendable {
    case prediction
    case schedule
}

struct StopTimes: Equatable, Sendable {
    let arrival: Date?
    let departure: Date?
}

/// Identifies a trip's stop occurrence; sequence distinguishes repeats when available.
struct TripStopKey: Hashable, Sendable {
    let tripId: String
    let stopId: String
    let stopSequence: Int?
}

enum StopCallAvailability: String, Sendable {
    case scheduledOnly
    case predicted
    /// Realtime timing was present recently but is missing now.
    case predictionLost
    case departed
    case canceled
}

/// Normalized prediction and schedule records before merging.
struct UnmergedTimingCalls: Equatable, Sendable {
    let predictionCalls: [TripStopTiming]
    let scheduleCalls: [TripStopTiming]
}

/// Arrival/departure timing from schedule, prediction, or both for one trip at one stop.
struct TripStopTiming: Equatable, Sendable {
    let key: TripStopKey
    let routeId: String
    let directionId: Int
    let vehicleId: String?
    let headsign: String?
    let isLastTrip: Bool?

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

    /// Source of the selected departure time.
    var effectiveDepartureSource: TimingSource? {
        if predicted?.departure != nil || predicted?.arrival != nil {
            return .prediction
        }
        if scheduled?.departure != nil || scheduled?.arrival != nil {
            return .schedule
        }
        return nil
    }
}

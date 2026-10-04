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

enum StopEventKind: String, Codable, Sendable {
    case arrival
    case departure
}

/// One selected arrival or departure time, including where that time came from.
struct SelectedStopTime: Equatable, Codable, Sendable {
    let time: Date
    let source: TimingSource
    let event: StopEventKind
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

    /// Arrival is preferred at a leg destination; departure is used if absent.
    var selectedArrivalTime: SelectedStopTime? {
        if let time = predicted?.arrival {
            return SelectedStopTime(time: time, source: .prediction, event: .arrival)
        }
        if let time = predicted?.departure {
            return SelectedStopTime(time: time, source: .prediction, event: .departure)
        }
        if let time = scheduled?.arrival {
            return SelectedStopTime(time: time, source: .schedule, event: .arrival)
        }
        if let time = scheduled?.departure {
            return SelectedStopTime(time: time, source: .schedule, event: .departure)
        }
        return nil
    }

    var effectiveArrival: Date? {
        selectedArrivalTime?.time
    }

    /// Displays arrival before departure for predictions, vice versa for schedules
    var selectedBoardingTime: SelectedStopTime? {
        if let time = predicted?.arrival {
            return SelectedStopTime(time: time, source: .prediction, event: .arrival)
        }
        if let time = predicted?.departure {
            return SelectedStopTime(time: time, source: .prediction, event: .departure)
        }
        if let time = scheduled?.departure {
            return SelectedStopTime(time: time, source: .schedule, event: .departure)
        }
        if let time = scheduled?.arrival {
            return SelectedStopTime(time: time, source: .schedule, event: .arrival)
        }
        return nil
    }

    var effectiveDeparture: Date? {
        selectedBoardingTime?.time
    }

}

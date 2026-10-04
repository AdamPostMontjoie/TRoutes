//
//  JourneyTimingState.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// The last route-wide timing result accepted by JourneyState.
struct JourneyTimingState: Equatable, Codable, Sendable {
    var refreshSessionId: UUID?
    var generation: UInt64 = 0
    var updatedAt: Date?
    var timing: JourneyTimingPlan?

    var status: JourneyTimingStatus {
        timing?.status ?? .idle
    }
}

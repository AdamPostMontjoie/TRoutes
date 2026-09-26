//
//  JourneyTimingState.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Version metadata and the last route-wide timing result accepted by JourneyState.
struct JourneyTimingState: Equatable, Codable, Sendable {
    var refreshSessionId: UUID?
    var generation: UInt64 = 0
    var updatedAt: Date?
    var timing: JourneyTimingPlan?

    var status: JourneyTimingStatus {
        timing?.status ?? .idle
    }
}

extension JourneyTimingState {
    private static let schemaVersion = 1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case refreshSessionId
        case generation
        case updatedAt
        case timing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            // Older timing snapshots cannot supply the selected stop-time event.
            // Only timing is reset; JourneyState can still restore route progress.
            self.init()
            return
        }
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported journey timing schema version \(version)"
            )
        }

        self.init()
        refreshSessionId = try container.decodeIfPresent(UUID.self, forKey: .refreshSessionId)
        generation = try container.decode(UInt64.self, forKey: .generation)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        timing = try container.decodeIfPresent(JourneyTimingPlan.self, forKey: .timing)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(refreshSessionId, forKey: .refreshSessionId)
        try container.encode(generation, forKey: .generation)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(timing, forKey: .timing)
    }
}

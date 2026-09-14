//
//  PredictionHistoryPolicy.swift
//  TRoutes
//

import Foundation

/// Policy values for interpreting a realtime event that disappears between
/// successful MBTA snapshots. These are intentionally isolated for later
/// tuning without changing merge mechanics.
struct PredictionHistoryPolicy {
    // MARK: - Policy values to validate with live prediction behavior

    let predictionLossGrace: TimeInterval = 30
    let retentionAfterEvent: TimeInterval = 10 * 60
}

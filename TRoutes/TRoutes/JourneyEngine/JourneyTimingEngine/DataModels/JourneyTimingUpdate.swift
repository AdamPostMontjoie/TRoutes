//
//  JourneyTimingUpdate.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Predictions for one existing JourneyState prediction target, projected from
/// the combined route-wide response. Match this ID against
/// `PredictionState.predictedStop.id` when applying the update.
struct PredictionSlice: Equatable, Sendable {
    let predictedStopId: UUID
    /// Up to three chronological board items, prioritizing live calls when
    /// selecting them and using schedules only to fill empty slots.
    let predictions: [TransitPrediction]
    /// Only calls present in the current predictions response. Tracking must not
    /// treat scheduled filler as an observed vehicle.
    let livePredictions: [TransitPrediction]
}

/// Transient output delivered to JourneyAction. This is not persisted directly;
/// JourneyAction copies its durable timing fields into JourneyTimingState.
struct JourneyTimingUpdate: Equatable, Sendable {
    let resolvedRouteId: UUID
    let context: JourneyTimingContext
    let refreshSessionId: UUID
    let generation: UInt64
    let fetchedAt: Date
    let status: JourneyTimingStatus
    let predictionSlices: [PredictionSlice]
    let recommendedDeparture: RecommendedDeparture?
    let currentLegArrival: Date?
    let destinationArrival: Date?
    let connection: TransferTiming?
}

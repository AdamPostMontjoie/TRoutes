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
    let predictions: [TransitPrediction]
}

/// Transient output delivered to JourneyAction. This is not persisted directly;
/// JourneyAction copies its durable timing fields into JourneyTimingState.
struct JourneyTimingUpdate: Equatable, Sendable {
    let resolvedRouteId: UUID
    let context: JourneyTimingContext
    let generation: UInt64
    let fetchedAt: Date
    let predictionSlices: [PredictionSlice]
    let recommendedDeparture: RecommendedDeparture?
    let currentLegArrival: Date?
    let destinationArrival: Date?
}

//
//  JourneyTimingUpdate.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Predictions for one existing JourneyState prediction target, projected from
/// the combined route-wide response.
struct PredictionSlice: Equatable, Sendable {
    let resolvedStopId: UUID
    let targetType: PredictionTargetType
    let predictions: [TransitPrediction]
}

/// Transient output delivered to JourneyAction. This is not persisted directly;
/// JourneyAction copies its durable timing fields into JourneyTimingState.
struct JourneyTimingUpdate: Equatable, Sendable {
    let routeId: UUID
    let generation: UInt64
    let fetchedAt: Date
    let predictionSlices: [PredictionSlice]
    let recommendedDeparture: RecommendedDeparture?
    let currentLegArrival: Date?
    let destinationArrival: Date?
}

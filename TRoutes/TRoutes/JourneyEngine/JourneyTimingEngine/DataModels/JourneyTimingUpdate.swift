//
//  JourneyTimingUpdate.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

struct PredictionSlice: Equatable, Sendable {
    let predictedStopId: UUID
    let displayPredictions: [TransitPrediction]
    let livePredictions: [TransitPrediction]
}

///Response from JourneyTimingEngine to JourneyEngine
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

//
//  PredictionManager.swift
//  TRoutes
//

import Foundation
import ComposableArchitecture

actor PredictionManager {
    static let shared = PredictionManager()
    
    @Dependency(\.mbtaClient) var mbtaClient
    
    func fetchPredictionsWithFallback(for predictionState: PredictionState, requestType: MBTARequestType) async throws -> [TransitPrediction] {
        let predictions = try await mbtaClient.fetchTransitTimes(predictionState.predictedStop, predictionState.acceptableRouteIds, requestType)
        
        if predictions.isEmpty {
            let schedules = try await mbtaClient.fetchSchedule(predictionState.predictedStop, requestType)
            return schedules.map { $0.asPrediction }
        }
        
        return predictions
    }
}

//
//  PredictionManager.swift
//  TRoutes
//

import Foundation
import ComposableArchitecture

actor PredictionManager {
    static let shared = PredictionManager()
    
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.date) var date
    
    private var inFlightRequests: [String: Task<[TransitPrediction], Error>] = [:]
    
    struct ScheduleCache {
        let schedules: [TransitSchedule]
        let expiration: Date
    }
    // Maps a unique request signature to cached schedules
    private var scheduleCache: [String: ScheduleCache] = [:]
    
    func fetchPredictionsWithFallback(for predictionState: PredictionState, requestType: MBTARequestType) async throws -> [TransitPrediction] {
        let targetKey = "\(predictionState.predictedStop.mbtaStopId)-\(predictionState.acceptableRouteIds.count)"
        
        if let existingTask = inFlightRequests[targetKey] {
            return try await existingTask.value
        }
        
        let task = Task {
            let now = date.now
            
            //Skip prediction request if next cached scheduled time is more than 10 minutes away
            if let cached = scheduleCache[targetKey], cached.expiration > now {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                
                if let firstSchedule = cached.schedules.first,
                   let scheduledTime = formatter.date(from: firstSchedule.display),
                   let currentTime = formatter.date(from: formatter.string(from: now)) {
                    
                    let minutesAway = Calendar.current.dateComponents([.minute], from: currentTime, to: scheduledTime).minute ?? 0
                    
                    if minutesAway > 10 {
                        return cached.schedules.map { $0.asPrediction }
                    }
                }
            }
            
            let predictions = try await mbtaClient.fetchTransitTimes(predictionState.predictedStop, predictionState.acceptableRouteIds, requestType)
            
            //Get scheduled times if no predictions available
            if predictions.isEmpty {
                let now = date.now
                //Reuse cached schedule if previously requested
                if let cached = scheduleCache[targetKey], cached.expiration > now {
                    return cached.schedules.map { $0.asPrediction }
                }
                
                let schedules = try await mbtaClient.fetchSchedule(predictionState.predictedStop, requestType)
                
                scheduleCache[targetKey] = ScheduleCache(schedules: schedules, expiration: now.addingTimeInterval(300))
                return schedules.map { $0.asPrediction }
            }
            
            return predictions
        }
        
        inFlightRequests[targetKey] = task
        defer { inFlightRequests[targetKey] = nil }
        return try await task.value
    }
    
    func clearScheduleCache(){
        scheduleCache = [:]
    }
}

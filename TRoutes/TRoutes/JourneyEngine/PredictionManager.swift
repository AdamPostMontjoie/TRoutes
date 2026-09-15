//
//  PredictionManager.swift
//  TRoutes
//
//  Created by Adam Post on 6/19/26.
//

import Foundation
import ComposableArchitecture

actor PredictionManager {
    static let shared = PredictionManager()
    
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.date) var date
    
    private var inFlightRequests: [String: Task<[TransitPrediction], Error>] = [:]
    private var inFlightTimingRequests: [TimingQueryKey: Task<UnmergedTimingCalls, Error>] = [:]
    
    struct ScheduleCache {
        let schedules: [TransitSchedule]
        let expiration: Date
    }
    // Maps a unique request signature to cached schedules
    private var scheduleCache: [String: ScheduleCache] = [:]

    struct TimingScheduleCache {
        let calls: [TripStopTiming]
        let expiration: Date
    }
    private var timingScheduleCache: [TimingQueryKey: TimingScheduleCache] = [:]
    
    func fetchPredictionsWithFallback(for predictionState: PredictionState, requestType: MBTARequestType) async throws -> [TransitPrediction] {
        let targetKey = "\(predictionState.predictedStop.mbtaStopId)-\(predictionState.acceptableRouteIds.count)"
        
        if let existingTask = inFlightRequests[targetKey] {
            return try await existingTask.value
        }
        
        let task = Task {
            let now = date.now
            
            //Skip prediction request if next cached scheduled time is more than 10 minutes away
            if let cached = scheduleCache[targetKey], cached.expiration > now {
                if let firstSchedule = cached.schedules.first,
                   let scheduledTime = firstSchedule.departureDate ?? firstSchedule.arrivalDate {
                    let minutesAway = Calendar.current.dateComponents([.minute], from: now, to: scheduledTime).minute ?? 0
                    
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

    /// Fetches the complete route timing input. Schedules are requested for every
    /// leg, even when live predictions exist, and are reused briefly between
    /// prediction refreshes. Filtering and merging remain JourneyTimingEngine's
    /// responsibility.
    func fetchTimingCalls(for plan: TimingQueryPlan, requestType: MBTARequestType) async throws -> UnmergedTimingCalls {
        let key = plan.key

        if let existingTask = inFlightTimingRequests[key] {
            return try await existingTask.value
        }

        let task = Task {
            let now = date.now
            let stopIds = plan.queriedStopIds.sorted()
            let routeIds = plan.queriedRouteIds.sorted()

            async let predictionCalls = mbtaClient.fetchTimingPredictions(
                stopIds,
                routeIds,
                requestType
            )

            let schedules: [TripStopTiming]
            if let cached = timingScheduleCache[key], cached.expiration > now {
                schedules = cached.calls
            } else {
                schedules = try await mbtaClient.fetchTimingSchedules(
                    stopIds,
                    routeIds,
                    requestType
                )
                timingScheduleCache[key] = TimingScheduleCache(
                    calls: schedules,
                    expiration: now.addingTimeInterval(300)
                )
            }

            let fetchedPredictionCalls = try await predictionCalls
            return UnmergedTimingCalls(
                predictionCalls: fetchedPredictionCalls,
                scheduleCalls: schedules
            )
        }

        inFlightTimingRequests[key] = task
        defer { inFlightTimingRequests[key] = nil }
        return try await task.value
    }
    
    func clearScheduleCache(){
        scheduleCache = [:]
        timingScheduleCache = [:]
    }
}

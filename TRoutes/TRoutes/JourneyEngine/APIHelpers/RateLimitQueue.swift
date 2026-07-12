//
//  RateLimitQueue.swift
//  TRoutes
//
//  Created by Adam Post on 7/10/26.
//

import Foundation
import DequeModule

enum MBTARequestType {
    case formRequest//removed soon, top priority for now
    case predictionRefresh //low priority, can be current stop or transfer
    case transferPrediction //medium priority
    case currentStopPrediction //high priority
    case vehiclePosition //high priority
    case patternMatching //highest priority, need it to display any trains at all
    
    var priorityValue: Int {
        switch self {
        case .formRequest: return 100
        case .patternMatching: return 90
        case .vehiclePosition: return 80
        case .currentStopPrediction: return 70
        case .transferPrediction: return 50
        case .predictionRefresh: return 10
        }
    }
}

enum RequestAvailability {
    case anyPriorityRequest
    case mediumPriorityRequests
    case highestPriorityRequests
    case noRequestsAvailable
}

///Queue that manages our API request limit.
///Locks up API call or drops based on priority
actor RateLimitQueue {
    static let shared = RateLimitQueue()
    
    // Limits
    private let limit = 20
    private let limitResetTime: TimeInterval = 60
    
    // The Queue
    private var requestHistory: Deque<Date> = []
    
    // Waitlist for High Priority Requests
    private var backedUpRequests: [(type: MBTARequestType, continuation: CheckedContinuation<Void, Error>)] = []
    
    // Anti-starvation counter for times refresh
    private var consecutiveLowPriorityDrops = 0
    
    var currentAvailability: RequestAvailability {
        cleanUp()
        let count = requestHistory.count
        if count >= limit {
            return .noRequestsAvailable
        } else if count >= 15 {
            return .highestPriorityRequests
        } else if count >= 12 {
            return .mediumPriorityRequests
        } else {
            return .anyPriorityRequest
        }
    }
    
    func checkRequestPriority(for type: MBTARequestType) -> Bool {
        let availability = currentAvailability
        
        switch type {
        case .predictionRefresh:
            if availability == .mediumPriorityRequests || availability == .highestPriorityRequests || availability == .noRequestsAvailable {
                // Anti-starvation mechanism
                if consecutiveLowPriorityDrops >= 3 {
                    consecutiveLowPriorityDrops = 0
                    return true // Force it through this time
                }
                consecutiveLowPriorityDrops += 1
                return false
            }
            consecutiveLowPriorityDrops = 0
            return true
            
        case .transferPrediction:
            if availability == .highestPriorityRequests || availability == .noRequestsAvailable {
                return false
            }
            return true
            
        default:
            return true
        }
    }
    
    /// Requests a token, enforcing limits and backup queue priority
    func acquireToken(for type: MBTARequestType) async throws {
        cleanUp()
        
        guard checkRequestPriority(for: type) else {
            throw MBTAError.rateLimitDropped
        }
        
        if requestHistory.count >= limit {
            try await withCheckedThrowingContinuation { continuation in
                backedUpRequests.append((type, continuation))
                backedUpRequests.sort { $0.type.priorityValue > $1.type.priorityValue }
                scheduleWakeUp()
            }
        }
        requestHistory.append(Date())
    }
    
    private func cleanUp() {
        let now = Date()
        while let oldest = requestHistory.first, now.timeIntervalSince(oldest) > limitResetTime {
            _ = requestHistory.popFirst()
        }
        print("requests cleared, queue size is now \(requestHistory.count)")
    }
    
    private func scheduleWakeUp() {
        guard let oldest = requestHistory.first else { return }
        let waitTime = limitResetTime - Date().timeIntervalSince(oldest)
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            wakeNextPending()
        }
    }
    
    private func wakeNextPending() {
        cleanUp()
        if requestHistory.count < limit, !backedUpRequests.isEmpty {
            print("ran backed up task")
            let next = backedUpRequests.removeFirst()
            next.continuation.resume()
        }
    }
}

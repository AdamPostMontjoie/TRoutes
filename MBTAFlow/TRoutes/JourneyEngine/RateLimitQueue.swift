//
//  RateLimitQueue.swift
//  TRoutes
//
//  Created by Adam Post on 7/10/26.
//

enum MBTARequestType {
    case formRequest//removed soon, top priority for now
    case predictionRefresh //low priority, can be current stop or transfer
    case transferPrediction //medium priority
    case currentStopPrediction //high priority
    case vehiclePosition //high priority
    case patternMatching //highest priority, need it to display any trains at all
}

enum RequestAvailability {
    case anyPriorityRequest
    case mediumPriorityRequests
    case highestPriorityRequests
    case noRequestsAvailable
}

///Queue that manages our API request limit
struct RateLimitQueue {
    
}

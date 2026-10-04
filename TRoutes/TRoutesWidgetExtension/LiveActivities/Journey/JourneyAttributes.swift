//
//  JourneyAttributes.swift
//  TRoutes
//
//  Created by Adam Post on 7/17/26.
//

import ActivityKit
import Foundation

struct JourneyAttributes: ActivityAttributes {
    public enum WidgetPredictionLoadingState: Codable, Hashable {
        case loading
        case loaded
        case unavailable(message: String)
    }
    
    public struct PredictionDisplay: Codable, Hashable {
        public let time: String
        public let badge: String?
        
        public init(time: String, badge: String? = nil) {
            self.time = time
            self.badge = badge
        }
    }
    
    public struct ContentState: Codable, Hashable {
        public let shortRouteName: String
        public let routeDestination: String
        public let currentLocationContext: String
        public let destinationContext: String?
        public let transferContext: String?
        public let currentTransitColor: String // Hex string
        public let currentTransitForegroundColor: String // Hex string
        public let currentIconName: String? // Missing icon
        public let isEndOfJourney: Bool
        public let journeyArrival: Date?
        
        public let activePredictions: [PredictionDisplay]
        public let activePredictionLoadingState: WidgetPredictionLoadingState?
        
        public let transferPredictions: [PredictionDisplay]?
        public let transferPredictionLoadingState: WidgetPredictionLoadingState?
        public let nextLegColor: String? // Hex string
        public let nextLegForegroundColor: String? // Hex string
        public let nextLegIconName: String?
    }
    
    // Any static properties (rarely change during a journey)
    public let journeyId: String

    static func etaText(_ arrival: Date, relativeTo now: Date) -> String {
        let remaining = arrival.timeIntervalSince(now)
        if remaining < 3600 {
            return "\(max(0, Int(ceil(remaining / 60))))m"
        }
        return arrival.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }
}

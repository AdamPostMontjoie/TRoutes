//
//  JourneyAttributes.swift
//  TRoutes
//
//  Created by Adam Post on 7/17/26.
//

import ActivityKit

struct JourneyAttributes: ActivityAttributes {
    public enum WidgetPredictionLoadingState: Codable, Hashable {
        case loading
        case loaded
        case unavailable(message: String)
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
        
        public let activePredictions: [String]
        public let activePredictionLoadingState: WidgetPredictionLoadingState?
        
        public let transferPredictions: [String]?
        public let transferPredictionLoadingState: WidgetPredictionLoadingState?
        public let nextLegColor: String? // Hex string
        public let nextLegForegroundColor: String? // Hex string
        public let nextLegIconName: String?
    }
    
    // Any static properties (rarely change during a journey)
    public let journeyId: String
}

//
//  LiveActivityManager.swift
//  TRoutes
//
//  Created by Adam Post on 7/17/26.
//

import Foundation
import ActivityKit
import SwiftUI

public actor LiveActivityManager {
    public static let shared = LiveActivityManager()
    
    private var listeningTask: Task<Void, Never>?
    
    public init() {}
    
    public func startListening() async {
        guard listeningTask == nil else { return }
        let stream = await JourneyEngine.shared.makeJourneyUpdateStream()
        
        listeningTask = Task {
            for await update in stream {
                switch update {
                case let .activeJourneyChanged(journey):
                    if let journey = journey {
                        await updateActivity(with: journey)
                    } else {
                        await endActivity()
                    }
                case .journeyTerminated:
                    await endActivity()
                }
            }
        }
    }
    
    private func updateActivity(with journey: JourneyState) async {
        let presentation = JourneyPresentationState(journey: journey)
        let activeLoadingState = mapLoadingState(presentation.activePredictionLoadingState)
        let transferLoadingState = mapLoadingState(presentation.transferPredictionLoadingState)

        let contentState = JourneyAttributes.ContentState(
            shortRouteName: presentation.shortRouteName,
            routeDestination: presentation.routeDestination,
            currentLocationContext: presentation.currentLocationContext,
            destinationContext: presentation.destinationContext,
            transferContext: presentation.transferContext,
            currentTransitColor: hexString(for: presentation.currentTransitType),
            currentTransitForegroundColor: foregroundHex(for: presentation.currentTransitType),
            currentIconName: presentation.currentTransitType?.iconName,
            isEndOfJourney: presentation.isEndOfJourney,
            activePredictions: presentation.activePredictions,
            activePredictionLoadingState: activeLoadingState,
            transferPredictions: presentation.transferPredictions,
            transferPredictionLoadingState: transferLoadingState,
            nextLegColor: hexString(for: presentation.nextLegTransitType),
            nextLegForegroundColor: foregroundHex(for: presentation.nextLegTransitType),
            nextLegIconName: presentation.nextLegTransitType?.iconName
        )
        
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        let activeActivities = Activity<JourneyAttributes>.activities
        if !activeActivities.isEmpty {
            for activity in activeActivities {
                await activity.update(content)
            }
        } else {
            let attributes = JourneyAttributes(journeyId: "active_journey")
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("Failed to start Live Activity: \(error.localizedDescription)")
            }
        }
    }
    
    private func endActivity() async {
        let activeActivities = Activity<JourneyAttributes>.activities
        for activity in activeActivities {
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }
    
    // MARK: - Helpers
    
    private func hexString(for transitType: TransitType?) -> String {
        guard let transitType = transitType else { return "#000000" }
        switch transitType {
        case .redLine: return "#DA291C"
        case .orangeLine: return "#ED8B00"
        case .greenLine: return "#00843D"
        case .blueLine: return "#003DA5"
        case .commuterRail: return "#80276C"
        case .mattapan: return "#DA291C"
        case .bus: return "#FFC72C"
        case .ferry: return "#008EAA"
        }
    }
    
    private func foregroundHex(for type: TransitType?) -> String {
        return (type?.color ?? .accentColor).isLightBackground ? "#000000" : "#FFFFFF"
    }
    
    private func mapLoadingState(_ state: PredictionLoadingState?) -> JourneyAttributes.WidgetPredictionLoadingState? {
        guard let state = state else { return nil }
        switch state {
        case .loading: return .loading
        case .loaded: return .loaded
        case .unavailable(_, let message): return .unavailable(message: message)
        }
    }
}

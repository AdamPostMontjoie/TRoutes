//
//  LiveActivityClient.swift
//  TRoutes
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import ActivityKit

//this is the dependency that updates the widget
struct LiveActivityClient {
    var startActivity: @Sendable (JourneyState) async -> Void
    var updateActivity: @Sendable (JourneyState) async -> Void
    var endActivity: @Sendable () async -> Void
}

extension LiveActivityClient: DependencyKey {
    static let liveValue = Self(
        startActivity: { state in
            
        },
        updateActivity: { state in
            
        },
        endActivity: {
            
        }
    )

    static let testValue: Self = .liveValue
}



extension DependencyValues {
    var liveActivityClient: LiveActivityClient {
        get { self[LiveActivityClient.self] }
        set { self[LiveActivityClient.self] = newValue }
    }
}

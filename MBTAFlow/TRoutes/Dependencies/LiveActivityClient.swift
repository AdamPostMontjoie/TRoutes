//
//  LiveActivityClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture

//this is the dependency that updates the widget
struct LiveActivityClient {
    var startActivity: @Sendable (UserRoute) async -> Void
    var updateActivity: @Sendable (JourneyState) async -> Void
    var endActivity: @Sendable () async -> Void
}

extension LiveActivityClient: DependencyKey {
    static let liveValue = Self(
        startActivity: { route in
        },
        updateActivity: { JourneyState in
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

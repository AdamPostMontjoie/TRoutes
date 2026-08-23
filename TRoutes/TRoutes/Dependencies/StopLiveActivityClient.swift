//
//  StopLiveActivityClient.swift
//  TRoutes
//

import ComposableArchitecture

struct StopLiveActivityClient {
    var start: @Sendable (StopLiveActivityRequest) async throws -> Void
}

extension StopLiveActivityClient: DependencyKey {
    static let liveValue = Self(
        start: { try await StopLiveActivityManager.shared.start($0) }
    )
}

extension DependencyValues {
    var stopLiveActivityClient: StopLiveActivityClient {
        get { self[StopLiveActivityClient.self] }
        set { self[StopLiveActivityClient.self] = newValue }
    }
}
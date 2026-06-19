//
//  JourneyClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import SwiftUI
import CoreLocation

enum locationError: Error, Equatable {
    case locationUnknown
    case accessDenied
    case hardwareFailure
    case setupDelayed
    case unknown
}

enum JourneyUpdate: Equatable {
    case activeJourneyChanged(JourneyState?)
}

///The layer between UI and the Journey Engine
struct JourneyClient {
    var beginRoute: @Sendable (RouteStruct) async -> AsyncStream<JourneyUpdate>
    var openSettings: @Sendable () -> Void
    var requestNewTimes: @Sendable () async -> Void
    var nextStop: @Sendable () async -> Void
    var atStop: @Sendable () async -> Void
    var getCurrentAuthorization: @Sendable () async -> CLAuthorizationStatus
    var requestLocationAuthorization: @Sendable () async -> Void
    var endRoute: @Sendable () async -> Void
}

extension JourneyClient: DependencyKey {
    static let liveValue = Self(
        beginRoute: { route in
            return await JourneyEngine.shared.beginRoute(route:route)
        },
        openSettings: {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            Task {
                await UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        },
        requestNewTimes: {
            await JourneyEngine.shared.fetchPredictions()
        },
        nextStop: {
            await JourneyEngine.shared.manualEventValidator(.nextStopTapped)
        },
        atStop: {
            await JourneyEngine.shared.manualEventValidator(.atStopTapped)
        },
        getCurrentAuthorization: {
            return await RegionManager.shared.authorizationStatus
        },
        requestLocationAuthorization: {
            return await RegionManager.shared.requestAlwaysAuthorization()
        },
        endRoute: {
            await JourneyEngine.shared.endRoute()
        }
        
    )
}

extension DependencyValues {
    var journeyClient: JourneyClient {
        get { self[JourneyClient.self] }
        set { self[JourneyClient.self] = newValue }
    }
}

//
//  LocationClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import CoreLocation

//will probably need this to set the corelocation boundaries for each stop
//interact with database client? interact with extension

struct LocationData: Equatable {
    var location = "location"
}

struct LocationClient {
    var currentLocation: @Sendable () async throws -> LocationData
    var locationStream: @Sendable () async -> AsyncStream<LocationData>
    var startMonitoring: @Sendable (RouteStruct) async throws -> Void
    var stopMonitoring: @Sendable () async throws -> Void
}

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        currentLocation: {
            LocationData()
        },
        locationStream: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        startMonitoring: { route in
            
        },
        stopMonitoring: {
            
        }
    )

    static let testValue: Self = .liveValue
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

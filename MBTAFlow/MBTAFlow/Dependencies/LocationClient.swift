//
//  LocationClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import CoreLocation

//this will use core location monitoring
//it tells us where we are, if we've crossed into a region
//we tell it when to setup and teardown regions

enum LocationEvent: Equatable {
    case enteredStop(stopId: String) //may need to change from stopId
    case exitedStop(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
    
    //add other
}

enum locationError: Error, Equatable {
    case locationUnknown
    case accessDenied
    case hardwareFailure
    case setupDelayed
    case unknown
}

struct LocationClient {
    var initializeManager: @Sendable (Stop) async -> Void
    var startMonitoring: @Sendable () async throws -> AsyncStream<LocationEvent>?
    var registerNextStopRegion: @Sendable (Stop) async throws -> Void
    var stopMonitoring: @Sendable () async throws -> Void
    var getCurrentAuthorization:@Sendable () -> CLAuthorizationStatus
    var requestLocationAuthorization: @Sendable () async -> Void
    var openSettings: @Sendable () -> Void
}

private actor LocationActor {
    var manager: RegionManager?
    
    func initializeManager(firstStop:Stop) async  {
        let manager =  await RegionManager(firstStop: firstStop)
        self.manager = manager
    }
    
    func start() async -> AsyncStream<LocationEvent>? {
        guard let manager else { return nil }
        
        await manager.startMonitoring()
        return await manager.eventStream
    }
    
    
    func registerNextStopRegion(stop: Stop) async throws {
        guard let manager else { return }
        await manager.registerRegion(for: stop)
    }
    
    func stop() async {
        guard let manager else { return }
        await manager.stopAll()
        self.manager = nil
    }
}

private let actor = LocationActor()

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        initializeManager: { stop in
            await actor.initializeManager(firstStop: stop)
        },
        startMonitoring: {
            return await actor.start()
        },
        registerNextStopRegion: { stop in
           try await actor.registerNextStopRegion(stop: stop)
            //error handling
        },
        stopMonitoring: {
            await actor.stop()
        },
        getCurrentAuthorization: {
            CLLocationManager().authorizationStatus
        },
        requestLocationAuthorization: {
            CLLocationManager().requestWhenInUseAuthorization()
            CLLocationManager().requestAlwaysAuthorization()
        },
        openSettings: {
            print("open settings")
        }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

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
    var startMonitoring: @Sendable (Stop) async throws -> AsyncStream<LocationEvent>
    var registerNextStopRegion: @Sendable (Stop) async throws -> Void
    var stopMonitoring: @Sendable () async throws -> Void
}

private actor LocationActor {
    var manager: RegionManager?
    
    func start(firstStop:Stop) async -> AsyncStream<LocationEvent> {
       
        let manager =  await RegionManager(firstStop: firstStop)
        self.manager = manager
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
        startMonitoring: { stop in
            return await actor.start(firstStop: stop)
        },
        registerNextStopRegion: { stop in
           try await actor.registerNextStopRegion(stop: stop)
            //error handling
        },
        stopMonitoring: {
            await actor.stop()
        }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

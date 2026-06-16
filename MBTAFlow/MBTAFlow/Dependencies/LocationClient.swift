//
//  LocationClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import CoreLocation
import SwiftUI

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
    var initializeManager: @Sendable () async -> Void
    var startMonitoring: @Sendable (Stop) async throws -> AsyncStream<LocationEvent>?
    var registerNextStopRegion: @Sendable (Stop) async throws -> Void
    var stopMonitoring: @Sendable () async throws -> Void
    var getCurrentAuthorization: @Sendable () async -> CLAuthorizationStatus
    var requestLocationAuthorization: @Sendable () async -> Void
    var openSettings: @Sendable () -> Void
}

private actor LocationActor {

    
    
    func initializeManager(fireDebugNotif: @escaping @Sendable(String) async -> Void) async  {
        await MainActor.run {
            RegionManager.shared.fireDebugNotif = fireDebugNotif
        }
        
    }
    
    func start(firstStop:Stop) async -> AsyncStream<LocationEvent>? {

        
        await RegionManager.shared.startMonitoring(firstStop:  firstStop)
        return await RegionManager.shared.eventStream
    }
    
    
    func registerNextStopRegion(stop: Stop) async throws {
       
        await RegionManager.shared.registerRegion(for: stop)
    }
    
    func stop() async {
        await RegionManager.shared.stopAll()
        
    }
}

private let actor = LocationActor()

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        initializeManager: { 
            @Dependency(\.notificationsClient) var notificationsClient
            await actor.initializeManager( fireDebugNotif: notificationsClient.debugStringNotification)
        },
        startMonitoring: { stop in
            return await actor.start(firstStop: stop)
        },
        registerNextStopRegion: { stop in
           try await actor.registerNextStopRegion(stop: stop)
            //error handling
        },
        stopMonitoring: {
            await actor.stop()
        },
        getCurrentAuthorization: {
            await MainActor.run {
                RegionManager.shared.authorizationStatus
            }
        },
        requestLocationAuthorization: {
            await MainActor.run {
                RegionManager.shared.requestAlwaysAuthorization()
            }
        },
        openSettings: {
           
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            Task {
                await UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            
        }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

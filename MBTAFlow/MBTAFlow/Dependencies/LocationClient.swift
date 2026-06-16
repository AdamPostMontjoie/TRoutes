//
//  LocationClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import CoreLocation
import SwiftUI

// This uses Core Location condition monitoring. It tells us when the user
// enters or exits the currently active stop region.
enum LocationEvent: Equatable {
    case enteredStop(stopId: String)
    case exitedStop(stopId: String)
    case authorizationDenied
    case monitoringFailed(stopId: String, error: locationError)
}

enum locationError: Error, Equatable {
    case locationUnknown
    case accessDenied
    case hardwareFailure
    case setupDelayed
    case unknown
}

struct LocationClient {
    var startMonitoring: @Sendable (Stop) async throws -> AsyncStream<LocationEvent>?
    var registerNextStopRegion: @Sendable (Stop) async throws -> Void
    var stopMonitoring: @Sendable () async throws -> Void
    var getCurrentAuthorization: @Sendable () -> CLAuthorizationStatus
    var requestLocationAuthorization: @Sendable () async -> Void
    var openSettings: @Sendable () -> Void
}

private actor LocationMonitorActor {
    private let monitorName = "MBTAFlowMonitor"
    private let radius: CLLocationDistance = 100

    private var monitor: CLMonitor?
    private var continuation: AsyncStream<LocationEvent>.Continuation?
    private var serviceSession: CLServiceSession?
    
    private var lastKnownState: [String: CLMonitor.Event.State] = [:]
    
    private var fireDebugNotif: (@Sendable (String) async -> Void)?
    
    

    func setDebugNotification(_ fireDebugNotif: @escaping @Sendable (String) async -> Void) {
        self.fireDebugNotif = fireDebugNotif
    }

    func startMonitoring(firstStop: Stop) async -> AsyncStream<LocationEvent> {
        let monitor = await monitor()
        let fireDebugNotif = self.fireDebugNotif
        
        let stream = AsyncStream<LocationEvent> { continuation in
                self.continuation = continuation
                
                let monitoringTask = Task {
                    await self.fireDebugNotif?("Started Route: \(firstStop.stopName)")
                    do {
                        for try await event in await monitor.events {
                            
                                if event.authorizationDenied || event.authorizationDeniedGlobally || event.authorizationRestricted {
                                    continuation.yield(.authorizationDenied)
                                    await fireDebugNotif?("unauthorized")
                                    continue
                                }
                                if event.conditionUnsupported || event.conditionLimitExceeded || event.persistenceUnavailable {
                                    await fireDebugNotif?("failed")
                                    //TODO: yield specific error
                                    continuation.yield(.monitoringFailed(stopId: event.identifier, error: .unknown))
                                    continue
                                }
                                let previous = lastKnownState[event.identifier]
                                let current = event.state
                                guard current != previous else {
                                       await fireDebugNotif?("Duplicate state \(current) for \(event.identifier), ignoring")
                                       continue
                                }
                                lastKnownState[event.identifier] = current
                                switch event.state {
                                    
                                    case .satisfied:
                                        await fireDebugNotif?("satifsied")
                                        continuation.yield(.enteredStop(stopId: event.identifier))
                                    case .unsatisfied:
                                        //only happens if previously we were satisfied
                                        if previous == .satisfied {
                                            await fireDebugNotif?("Exited \(event.identifier)")
                                            continuation.yield(.exitedStop(stopId: event.identifier))
                                        }
                                    default:
                                        await fireDebugNotif?("default")
                                        break
                                
                            }
                        }
                    } catch {
                        print("CLMonitor event stream failed: \(error)")
                        continuation.finish()
                    }
                }
                
                continuation.onTermination = { _ in
                    monitoringTask.cancel()
                }
            }
        
        await registerRegion(for: firstStop)
        if self.serviceSession == nil {
            self.serviceSession = CLServiceSession(authorization: .always)
        }

        return stream
    }

    func registerRegion(for stop: Stop) async {
        let monitor = await monitor()
        await removeAllRegions()
        //reset stop
        lastKnownState.removeAll()

        let center = CLLocationCoordinate2D(
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        let condition = CLMonitor.CircularGeographicCondition(
            center: center,
            radius: radius
        )

        await monitor.add(condition, identifier: stop.stopName, assuming: .unknown)
        
        if let record = await monitor.record(for: stop.stopName) {
            let initialState = record.lastEvent.state
            lastKnownState[stop.stopName] = initialState
            switch record.lastEvent.state {
            //already inside
            case .satisfied:
                await self.fireDebugNotif?("Initial State: Inside \(stop.stopName)")
                self.continuation?.yield(.enteredStop(stopId: stop.stopName))
            case .unsatisfied:
                await self.fireDebugNotif?("Initial State: Outside \(stop.stopName)")
            default:
                await self.fireDebugNotif?("Initial State: Unknown \(stop.stopName)")
            }
        }
        print("CoreLocation: registered CLMonitor condition for \(stop.stopName) (Radius: \(Int(radius))m)")
    }

    func stopMonitoring() async {
        if let monitor {
            await removeAllRegions()
        }
        serviceSession = nil
        continuation?.finish()
        continuation = nil
    }

    private func monitor() async -> CLMonitor {
        if let monitor {
            return monitor
        }

        let monitor = await CLMonitor(monitorName)
        self.monitor = monitor
        return monitor
    }

    private func removeAllRegions() async {
        if let monitor {
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
                print("removed region for \(identifier)")
            }
        }
    }
}

private let locationMonitorActor = LocationMonitorActor()

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        
        startMonitoring: { stop in
            @Dependency(\.notificationsClient) var notificationsClient
            await locationMonitorActor.setDebugNotification(notificationsClient.debugStringNotification)
            return await locationMonitorActor.startMonitoring(firstStop: stop)
        },
        registerNextStopRegion: { stop in
            await locationMonitorActor.registerRegion(for: stop)
        },
        stopMonitoring: {
            await locationMonitorActor.stopMonitoring()
        },
        getCurrentAuthorization: {
            CLLocationManager().authorizationStatus
        },
        requestLocationAuthorization: {
            CLLocationManager().requestAlwaysAuthorization()
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

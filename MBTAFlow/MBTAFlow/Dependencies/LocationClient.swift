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

    func startMonitoring(firstStop: Stop) async -> AsyncStream<LocationEvent> {
        let monitor = await monitor()
        await registerRegion(for: firstStop)
        if self.serviceSession == nil {
            self.serviceSession = CLServiceSession(authorization: .always)
        }

        return AsyncStream<LocationEvent> { continuation in
            // Stream is created once, continuation stored for delegate use
            self.continuation = continuation
        
            
            let monitoringTask = Task {
                do {
                    for try await event in await monitor.events {
                        if event.authorizationDenied || event.authorizationDeniedGlobally || event.authorizationRestricted {
                            continuation.yield(.authorizationDenied)
                            continue
                        }
                        if event.conditionUnsupported || event.conditionLimitExceeded || event.persistenceUnavailable {
                            continuation.yield(.monitoringFailed(stopId: event.identifier, error: .unknown))
                            continue
                        }
                        switch event.state {
                        case .satisfied:
                            continuation.yield(.enteredStop(stopId: event.identifier))
                        case .unsatisfied:
                            continuation.yield(.exitedStop(stopId: event.identifier))
                        default:
                            break
                        }
                    }
                } catch {
                    print("CoreLocation: CLMonitor event stream failed: \(error)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                monitoringTask.cancel()
            }
        }
    }

    func registerRegion(for stop: Stop) async {
        let monitor = await monitor()
        await removeAllRegions(from: monitor)

        let center = CLLocationCoordinate2D(
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        let condition = CLMonitor.CircularGeographicCondition(
            center: center,
            radius: radius
        )

        await monitor.add(condition, identifier: stop.stopName, assuming: .unsatisfied)
        print("CoreLocation: registered CLMonitor condition for \(stop.stopName) (Radius: \(Int(radius))m)")
    }

    func stopMonitoring() async {
        if let monitor {
            await removeAllRegions(from: monitor)
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

    private func removeAllRegions(from monitor: CLMonitor) async {
        for identifier in await monitor.identifiers {
            await monitor.remove(identifier)
            print("removed region for \(identifier)")
        }
    }
}

private let locationMonitorActor = LocationMonitorActor()

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        startMonitoring: { stop in
            await locationMonitorActor.startMonitoring(firstStop: stop)
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

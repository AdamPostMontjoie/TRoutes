//
//  LocationManager.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/7/26.
//

import CoreLocation
import ComposableArchitecture

@MainActor
class RegionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: AsyncStream<LocationEvent>.Continuation?
    private var currentStop: Stop?
    
    //guards against double state notifications
    private var lastKnownState: CLRegionState?
    
    var fireDebugNotif: ( @Sendable(String) async -> Void)?
    // Stream is created once, continuation stored for delegate use
    lazy var eventStream: AsyncStream<LocationEvent> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    print("stream termination")
                    await self?.clearMonitoredRegions()
                }
            }
        }
    }()
    
    static let shared = RegionManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        // throw if not authorized somewhere in here, in case user disables location access mid journey
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func handleLocationLaunch() {
        locationManager.delegate = self
        Task {
            await fireDebugNotif?("App launched for CoreLocation event")
        }
        locationManager.monitoredRegions.forEach { region in
            locationManager.requestState(for: region)
        }
    }
    
    func startMonitoring(firstStop:Stop) {
        self.currentStop = firstStop
        if currentStop != nil{
            registerRegion(for: currentStop!)
        } else {
            return
        }
    }
    
    func registerRegion(for stop: Stop) {
        //remove all regions, 1 monitored maximum
        self.currentStop = stop
        self.lastKnownState = nil
        clearMonitoredRegions()
        let coordinate = CLLocationCoordinate2D(
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        let region = CLCircularRegion(
            center: coordinate,
            radius: 100,
            identifier: stop.stopName
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
                    print("⚠️ CoreLocation: Monitoring NOT available on this device/simulator.")
                    return
                }
        
        print("📍 CoreLocation: REGISTERED region for \(stop.stopName) (Radius: 100m)")
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        locationManager.startMonitoring(for: region)
    }
    
    private func authorizationDenied(){
        continuation?.yield(.authorizationDenied)
       // self.stopAll()
    }
    
    func stopAll() {
        clearMonitoredRegions()
        continuation?.finish()
    }
    private func clearMonitoredRegions(){
        locationManager.monitoredRegions.forEach {
            print("Removing montitored region")
            locationManager.stopMonitoring(for: $0)
        }
    }
    
    func locationManager( _ manager: CLLocationManager, didStartMonitoringFor region: CLRegion)
    {
        //when we setup secondary regions, we will need a way to check which one this is
        
        //request state only once we know that we're monitoring so we can avoid false unknowns during monitoring start
        locationManager.requestState(for: region)
    }
    //checks if we're already inside of the zone
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        //iOS may automatically fire did determine state on start monitoring, ignore if no change
        guard state != lastKnownState else { return }
        lastKnownState = state
            switch state {
            case .inside:
                Task {
                await fireDebugNotif?("Inside \(region.identifier)")
                print("📍 CoreLocation: Already inside region upon registration.")
                continuation?.yield(.enteredStop(stopId: region.identifier))
            }
            case .outside:
                Task {
                    await fireDebugNotif?("outside \(region.identifier)")
            }
            case .unknown:
                //we will need to handle unknown location with a fallback
                Task {
                    await fireDebugNotif?("unkown \(region.identifier)")
            }
            default:
                Task {
                    await fireDebugNotif?("d falt")
            }
                
            }
        }
    
    //on enter
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("entered region")
        Task {
            await fireDebugNotif?("Entered Region \(region.identifier)")
        }
        continuation?.yield(.enteredStop(stopId: region.identifier))
    }
    
    //on exit
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("exited region")
        Task {
            await fireDebugNotif?("Exited Region \(region.identifier)")
        }
        continuation?.yield(.exitedStop(stopId: region.identifier))
        
        // Stop monitoring the region we just left
        if let exitedRegion = manager.monitoredRegions.first(where: { $0.identifier == region.identifier }) {
            //deprecated
            manager.stopMonitoring(for: exitedRegion)
        }
    }
    
    //using this from CLLocationManager might be a solution to underground gps disconnnect, worth a try
    //func startMonitoringSignificantLocationChanges()
    
    
    
    //on error
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let id = region?.identifier {
            let mappedError: locationError
            if let clError = error as? CLError {
                    switch clError.code {
                    case .locationUnknown:
                        mappedError = .locationUnknown
                    case .regionMonitoringDenied:
                        mappedError = .accessDenied
                    case .regionMonitoringFailure:
                        mappedError = .hardwareFailure
                    case .regionMonitoringSetupDelayed:
                        mappedError = .setupDelayed
                    default:
                        mappedError = .unknown
                    }
                } else {
                    mappedError = .unknown
                }
            Task {
                await fireDebugNotif?("Debug Error: \(error)")
            }
            continuation?.yield(.monitoringFailed(stopId: id, error: mappedError ))
        }
    }
}

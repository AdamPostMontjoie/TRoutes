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
    private var continuation: AsyncStream<JourneyCommand>.Continuation?
    private var currentStop: Stop?
    
    // Guards against double state events.
    private var lastKnownState: CLRegionState?
    
    static let shared = RegionManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        // throw if not authorized somewhere in here, in case user disables location access mid journey
    }
    
    func makeEventStream() -> AsyncStream<JourneyCommand> {
        AsyncStream { continuation in
            self.continuation = continuation
            
            continuation.onTermination = { _ in
                print("location event stream termination")
            }
        }
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
        //potential fallback
     //   locationManager.startMonitoringSignificantLocationChanges()
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
            identifier: stop.mbtaStopId
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
        self.stopAll()
    }
    
    func stopAll() {
        clearMonitoredRegions()
        self.currentStop = nil
        self.lastKnownState = nil
        continuation?.finish()
        continuation = nil
        //clear persisted user defaults
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
                print("📍 CoreLocation: Already inside region upon registration.")
                continuation?.yield(.executeEntry(stopId: region.identifier))
            case .outside:
                break
            case .unknown:
                //we will need to handle unknown location with a fallback
                break
            default:
                break
            }
        }
    
    //on enter
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("entered region")
        continuation?.yield(.executeEntry(stopId: region.identifier))
    }
    
    //on exit
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("exited region")
        continuation?.yield(.executeExit(stopId: region.identifier))
        //stopping monitoring should be handled when new region is registered
    }
    
    
    
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
            continuation?.yield(.monitoringFailed(stopId: id, error: mappedError ))
        }
    }
}

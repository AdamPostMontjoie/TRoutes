//
//  LocationManager.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/7/26.
//

import CoreLocation

@MainActor
class RegionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: AsyncStream<LocationEvent>.Continuation?
    private var currentStop: Stop?
    private var currentIndex: Int = 0
    
    // Stream is created once, continuation stored for delegate use
    lazy var eventStream: AsyncStream<LocationEvent> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopAll()
                }
            }
        }
    }()
    
    init(firstStop:Stop) {
        super.init()
        self.currentStop = firstStop
        locationManager.delegate = self
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            // Only ask for foreground to start the chain
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            // Catch-all for returning users who downgraded permissions
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    func startMonitoring() {
        if currentStop != nil{
            registerRegion(for: currentStop!)
        } else {
            return
        }
    }
    
    func registerRegion(for stop: Stop) {
        //remove all regions, 1 monitored maximum
        locationManager.monitoredRegions.forEach {
                locationManager.stopMonitoring(for: $0)
        }
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
                
        locationManager.startMonitoring(for: region)
        print("📍 CoreLocation: REGISTERED region for \(stop.stopName) (Radius: 100m)")
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        locationManager.startMonitoring(for: region)
    }
    
    private func authorizationDenied(){
        continuation?.yield(.authorizationDenied)
       // self.stopAll()
    }
    
    private func stopAll() {
        locationManager.monitoredRegions.forEach {
            locationManager.stopMonitoring(for: $0)
        }
        continuation?.finish()
    }
    //on enter
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        continuation?.yield(.enteredStop(stopId: region.identifier))
    }
    
    //on exit
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        continuation?.yield(.exitedStop(stopId: region.identifier))
        
        // Stop monitoring the region we just left
        if let exitedRegion = manager.monitoredRegions.first(where: { $0.identifier == region.identifier }) {
            manager.stopMonitoring(for: exitedRegion)
        }
    }
    
    //location permissions changed
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
            case .authorizedWhenInUse:
                manager.requestAlwaysAuthorization()
            case .authorizedAlways:
                print("Location Authorized")
            case .restricted, .denied:
                self.authorizationDenied()
            default:
                break
        }
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

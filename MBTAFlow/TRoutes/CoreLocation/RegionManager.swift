//
//  LocationManager.swift
//  TRoutes
//
//  Created by Adam Post on 6/7/26.
//

import CoreLocation
import ComposableArchitecture

@MainActor
class RegionManager: NSObject, CLLocationManagerDelegate {
    
    // MARK: - Types & Properties
    
    private enum SurfaceTrackingMode {
        case idle
        case cruising
        case approaching
    }
    
    private enum TrackingContext {
        case arrivingOnFoot(GTFSTransitType)
        case emergingFromUnderground(GTFSTransitType)
        case ridingAlongSurface(GTFSTransitType)
        
        var entryDistance: CLLocationDistance {
            switch self {
            case .arrivingOnFoot(.bus): return 20
            case .arrivingOnFoot(.lightRail): return 30
            case .arrivingOnFoot(.heavyRail): return 60
            case .arrivingOnFoot(.commuterRail): return 60
            case .arrivingOnFoot(.ferry): return 80
            case .emergingFromUnderground(.bus): return 80
            case .emergingFromUnderground(.lightRail): return 100
            case .emergingFromUnderground(.heavyRail): return 140
            case .emergingFromUnderground(.commuterRail): return 140
            case .emergingFromUnderground(.ferry): return 160
            case .ridingAlongSurface(.bus): return 30
            case .ridingAlongSurface(.lightRail): return 40
            case .ridingAlongSurface(.heavyRail): return 80
            case .ridingAlongSurface(.commuterRail): return 100
            case .ridingAlongSurface(.ferry): return 120
            }
        }
        
        var exitDistance: CLLocationDistance {
            switch self {
            case .arrivingOnFoot(.bus): return 40
            case .arrivingOnFoot(.lightRail): return 50
            case .arrivingOnFoot(.heavyRail): return 90
            case .arrivingOnFoot(.commuterRail): return 100
            case .arrivingOnFoot(.ferry): return 120
            case .emergingFromUnderground(.bus): return 120
            case .emergingFromUnderground(.lightRail): return 140
            case .emergingFromUnderground(.heavyRail): return 200
            case .emergingFromUnderground(.commuterRail): return 200
            case .emergingFromUnderground(.ferry): return 220
            case .ridingAlongSurface(.bus): return 40
            case .ridingAlongSurface(.lightRail): return 60
            case .ridingAlongSurface(.heavyRail): return 100
            case .ridingAlongSurface(.commuterRail): return 120
            case .ridingAlongSurface(.ferry): return 140
            }
        }
        
        var requiredAccuracy: CLLocationAccuracy {
            switch self {
            case .arrivingOnFoot(.bus): return 35
            case .arrivingOnFoot(.lightRail): return 45
            case .arrivingOnFoot(.heavyRail): return 65
            case .arrivingOnFoot(.commuterRail): return 65
            case .arrivingOnFoot(.ferry): return 85
            case .emergingFromUnderground(.bus): return 120
            case .emergingFromUnderground(.lightRail): return 140
            case .emergingFromUnderground(.heavyRail): return 200
            case .emergingFromUnderground(.commuterRail): return 200
            case .emergingFromUnderground(.ferry): return 220
            case .ridingAlongSurface(.bus): return 50
            case .ridingAlongSurface(.lightRail): return 60
            case .ridingAlongSurface(.heavyRail): return 100
            case .ridingAlongSurface(.commuterRail): return 120
            case .ridingAlongSurface(.ferry): return 140
            }
        }
        
        var approachRegionRadius: CLLocationDistance {
            switch self {
            case .arrivingOnFoot: return 200
            case .emergingFromUnderground: return 300
            case .ridingAlongSurface: return 200
            }
        }
    }

    private let locationManager = CLLocationManager()
    private var continuation: AsyncStream<JourneyCommand>.Continuation?
    private var currentStop: ResolvedStop?
    private var trackingContext: TrackingContext = .arrivingOnFoot(.bus)
    private var surfaceTrackingMode: SurfaceTrackingMode = .idle
    private var hasYieldedEntryForCurrentStop = false
    private var hasYieldedExitForCurrentStop = false
    
    // Guards against double state events.
    private var lastKnownState: CLRegionState?
    
    static let shared = RegionManager()
    
    var currentDeviceLocation: CLLocation? {
        return locationManager.location
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    // MARK: - Lifecycle & Stream
    
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
    
    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func authorizationDenied(){
        continuation?.yield(.locationAuthorizationDenied)
        self.killManager()
    }
    
    func stopFunction() {
        clearMonitoredRegions()
        locationManager.stopUpdatingLocation()
        self.currentStop = nil
        self.lastKnownState = nil
        self.surfaceTrackingMode = .idle
        self.hasYieldedEntryForCurrentStop = false
        self.hasYieldedExitForCurrentStop = false
    }
    
    func killManager(){
        clearMonitoredRegions()
        locationManager.stopUpdatingLocation()
        self.currentStop = nil
        self.lastKnownState = nil
        self.surfaceTrackingMode = .idle
        self.hasYieldedEntryForCurrentStop = false
        self.hasYieldedExitForCurrentStop = false
        continuation?.finish()
        continuation = nil
    }
    
    // MARK: - Region Setup
    
    func registerRegion(
        for stop: ResolvedStop,
        previousMonitoringMode: MonitoringMode?
    ) {
        let context = trackingContext(
            for: stop,
            previousMonitoringMode: previousMonitoringMode
        )
        //remove all regions, 1 monitored maximum
        self.currentStop = stop
        self.trackingContext = context
        self.lastKnownState = nil
        self.surfaceTrackingMode = .cruising
        self.hasYieldedEntryForCurrentStop = false
        self.hasYieldedExitForCurrentStop = false
        clearMonitoredRegions()
        let coordinate = CLLocationCoordinate2D(
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        let region = CLCircularRegion(
            center: coordinate,
            radius: context.approachRegionRadius,
            identifier: stop.mbtaStopId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        startCruisingLocationUpdates()

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
                    print("⚠️ CoreLocation: Monitoring NOT available on this device/simulator.")
                    return
                }
        
        print("📍 CoreLocation: REGISTERED region for \(stop.stopName) (Context: \(context), Radius: \(context.approachRegionRadius)m)")
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        locationManager.startMonitoring(for: region)
    }
    
    private func trackingContext(
        for stop: ResolvedStop,
        previousMonitoringMode: MonitoringMode?
    ) -> TrackingContext {
        if stop.journeyRole == .boarding {
            return .arrivingOnFoot(stop.transitType)
        }
        
        if previousMonitoringMode == .surface {
            return .ridingAlongSurface(stop.transitType)
        }
        
        return .emergingFromUnderground(stop.transitType)
    }
    
    private func clearMonitoredRegions(){
        locationManager.monitoredRegions.forEach {
            print("Removing montitored region")
            locationManager.stopMonitoring(for: $0)
        }
    }
    
    // MARK: - CLLocationManagerDelegate (Authorization)
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            if self.currentStop != nil {
                self.authorizationDenied()
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate (Region Monitoring)
    
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
                print("📍 CoreLocation: Nearby to stop, inside approach region.")
                handleApproachRegionEntered(regionId: region.identifier)
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
        print("entered approach region")
        handleApproachRegionEntered(regionId: region.identifier)
    }
    
    //on exit - no longer used for exit detection, GPS distance handles exits
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("exited approach region for \(region.identifier) - no action, GPS distance handles exit")
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

    // MARK: - CLLocationManagerDelegate (Location Updates)

    private func startCruisingLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .otherNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.startUpdatingLocation()
    }

    private func startApproachingLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .otherNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        locationManager.startUpdatingLocation()
    }

    private func handleApproachRegionEntered(regionId: String) {
        guard currentStop?.mbtaStopId == regionId,
              surfaceTrackingMode != .approaching else { return }

        surfaceTrackingMode = .approaching
        startApproachingLocationUpdates()
        continuation?.yield(.approachingStop(stopId: regionId))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            print("RGM: Polling location [\(location.coordinate.latitude), \(location.coordinate.longitude)]")
        }
        guard let stop = currentStop,
              let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= trackingContext.requiredAccuracy,
              abs(location.timestamp.timeIntervalSinceNow) <= 10
        else { return }

        let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        let distance = location.distance(from: stopLocation)

        if distance <= trackingContext.entryDistance, !hasYieldedEntryForCurrentStop {
            hasYieldedEntryForCurrentStop = true
            hasYieldedExitForCurrentStop = false
            surfaceTrackingMode = .approaching
            startApproachingLocationUpdates()
            continuation?.yield(.executeEntry(stopId: stop.mbtaStopId))
            return
        }

        if hasYieldedEntryForCurrentStop,
           distance >= trackingContext.exitDistance,
           !hasYieldedExitForCurrentStop {
            hasYieldedExitForCurrentStop = true
            continuation?.yield(.executeExit(stopId: stop.mbtaStopId))
            return
        }
    }
}

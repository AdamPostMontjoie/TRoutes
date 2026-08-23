import CoreLocation
import ComposableArchitecture

@MainActor
class NearbyStopsManager: NSObject, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    private var continuation: AsyncStream<NearbyStopsUpdate>.Continuation?
    
    private var lastDisplayLocation: CLLocation?
    private var lastSearchLocation: CLLocation?
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var isLiveActivityBackgroundSessionActive = false
    
    static let shared = NearbyStopsManager()
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.distanceFilter = 10
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    
    func makeUpdateStream() -> AsyncStream<NearbyStopsUpdate> {
        AsyncStream { continuation in
            self.continuation = continuation
            
            continuation.onTermination = { _ in
                print("NearbyStops stream terminated")
            }
            
            // Start location updates immediately when the stream is created
            let status = locationManager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdatingLocation()
                
                // If we already have a location, yield it immediately
                if let location = locationManager.location {
                    self.lastDisplayLocation = location
                    self.lastSearchLocation = location
                    continuation.yield(.displayCoordinates(location.coordinate))
                    continuation.yield(.searchCoordinates(location.coordinate))
                }
            } else if status == .denied || status == .restricted {
                continuation.yield(.authorizationDenied)
            }
            // If .notDetermined, we do nothing and wait for authorization status to change.
        }
    }
    
    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startLiveActivityBackgroundSession() -> Bool {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return false
        }

        isLiveActivityBackgroundSessionActive = true
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = CLBackgroundActivitySession()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .other
        locationManager.startUpdatingLocation()
        return true
    }

    func stopLiveActivityBackgroundSession() {
        isLiveActivityBackgroundSessionActive = false
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true

        if continuation == nil {
            locationManager.stopUpdatingLocation()
        } else {
            locationManager.startUpdatingLocation()
        }
    }
    
    func stopFunction() {
        continuation?.finish()
        continuation = nil

        guard !isLiveActivityBackgroundSessionActive else { return }
        locationManager.stopUpdatingLocation()
        lastDisplayLocation = nil
        lastSearchLocation = nil
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            continuation?.yield(.authorizationDenied)
            if isLiveActivityBackgroundSessionActive {
                Task {
                    await StopLiveActivityManager.shared.end()
                }
            }
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            if continuation != nil {
                continuation?.yield(.authorizationGranted)
                manager.startUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let lastDisplayLocation {
            if location.distance(from: lastDisplayLocation) >= 10 {
                self.lastDisplayLocation = location
                continuation?.yield(.displayCoordinates(location.coordinate))
            }
        } else {
            lastDisplayLocation = location
            continuation?.yield(.displayCoordinates(location.coordinate))
        }

        if let lastSearchLocation {
            if location.distance(from: lastSearchLocation) >= 200 {
                self.lastSearchLocation = location
                continuation?.yield(.searchCoordinates(location.coordinate))
            }
        } else {
            lastSearchLocation = location
            continuation?.yield(.searchCoordinates(location.coordinate))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                continuation?.yield(.error(.locationUnknown))
            case .denied:
                continuation?.yield(.error(.accessDenied))
            default:
                continuation?.yield(.error(.unknown))
            }
        } else {
            continuation?.yield(.error(.unknown))
        }
    }
}

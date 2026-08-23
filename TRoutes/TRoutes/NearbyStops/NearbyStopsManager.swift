import CoreLocation
import ComposableArchitecture

@MainActor
class NearbyStopsManager: NSObject, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    private var continuation: AsyncStream<NearbyStopsUpdate>.Continuation?
    
    private var lastDisplayLocation: CLLocation?
    private var lastSearchLocation: CLLocation?
    
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
    
    func stopFunction() {
        locationManager.stopUpdatingLocation()
        lastDisplayLocation = nil
        lastSearchLocation = nil
        continuation?.finish()
        continuation = nil
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            continuation?.yield(.authorizationDenied)
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

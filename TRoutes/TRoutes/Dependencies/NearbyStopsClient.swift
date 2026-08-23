import ComposableArchitecture
import CoreLocation
import UIKit

enum NearbyStopsUpdate: Equatable {
    case refreshCoordinates(CLLocationCoordinate2D)
    case displayCoordinates(CLLocationCoordinate2D)
    case error(NearbyStopsError)
    case authorizationDenied
    case authorizationGranted
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

enum NearbyStopsError: Error, Equatable {
    case locationUnknown
    case accessDenied
    case unknown
}

struct NearbyStopsClient {
    var makeUpdateStream: @Sendable () async -> AsyncStream<NearbyStopsUpdate>
    var getCurrentAuthorization: @Sendable () async -> CLAuthorizationStatus
    var requestLocationAuthorization: @Sendable () async -> Void
    var setRefreshOrigin: @Sendable (CLLocationCoordinate2D) async -> Void
    var openSettings: @Sendable () -> Void
    var stopUpdates: @Sendable () async -> Void
}

extension NearbyStopsClient: DependencyKey {
    static let liveValue = Self(
        makeUpdateStream: { await NearbyStopsManager.shared.makeUpdateStream() },
        getCurrentAuthorization: { await NearbyStopsManager.shared.authorizationStatus },
        requestLocationAuthorization: { await NearbyStopsManager.shared.requestLocationAuthorization() },
        setRefreshOrigin: { await NearbyStopsManager.shared.setRefreshOrigin($0) },
        openSettings: {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        },
        stopUpdates: { await NearbyStopsManager.shared.stopFunction() }
    )
}

extension DependencyValues {
    var nearbyStopsClient: NearbyStopsClient {
        get { self[NearbyStopsClient.self] }
        set { self[NearbyStopsClient.self] = newValue }
    }
}

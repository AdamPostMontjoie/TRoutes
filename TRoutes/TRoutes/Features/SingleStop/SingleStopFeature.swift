//
//  SingleStopFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture
import CoreLocation

@Reducer
struct SingleStopFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.hasValidApiKey) var hasValidApiKey = false
        @Presents var destination: Destination.State?
        
        var stopsList = StopsListFeature.State()
        var search = StopSearchFeature.State()
        var path = StackState<SearchedStationFeature.State>()
        
        var locationPermissionDenied = false
        var userCoordinates: CLLocationCoordinate2D?
    }
    
    enum Action: Equatable {
        case onAppear
        case apiKeyLinkTapped
        case onSettingsButtonTapped
        case requestLocationTapped
        
        case startListeningToLocation
        case locationAuthorizationStatusReceived(CLAuthorizationStatus)
        case locationPermissionRequestFinished(CLAuthorizationStatus)
        case locationUpdateReceived(NearbyStopsUpdate)
        
        case stopsList(StopsListFeature.Action)
        case search(StopSearchFeature.Action)
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<SearchedStationFeature>)
    }
    
    @Dependency(\.nearbyStopsClient) var nearbyStopsClient
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let getAuth = nearbyStopsClient.getCurrentAuthorization
                return .run { send in
                    let status = await getAuth()
                    await send(.locationAuthorizationStatusReceived(status))
                    await send(.startListeningToLocation)
                }
                
            case .requestLocationTapped:
                let getAuth = nearbyStopsClient.getCurrentAuthorization
                let requestAuth = nearbyStopsClient.requestLocationAuthorization
                let openSettings = nearbyStopsClient.openSettings
                return .run { _ in
                    let status = await getAuth()
                    if status == .notDetermined {
                        await requestAuth()
                    } else if status == .denied || status == .restricted {
                        openSettings()
                    }
                }
                
            case let .locationAuthorizationStatusReceived(status):
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    state.locationPermissionDenied = false
                case .notDetermined, .denied, .restricted:
                    state.locationPermissionDenied = true
                @unknown default:
                    break
                }
                return .none
                
            case .startListeningToLocation:
                let makeStream = nearbyStopsClient.makeUpdateStream
                return .run { send in
                    for await update in await makeStream() {
                        await send(.locationUpdateReceived(update))
                    }
                }
                
            case let .locationUpdateReceived(update):
                switch update {
                case .coordinates(let coords):
                    print("📍 User coords updated: \(coords.latitude), \(coords.longitude)")
                    state.locationPermissionDenied = false
                    state.userCoordinates = coords
                    return .send(.stopsList(.fetchNearby(latitude: coords.latitude, longitude: coords.longitude)))
                case .authorizationGranted:
                    state.locationPermissionDenied = false
                case .authorizationDenied:
                    state.locationPermissionDenied = true
                case .error:
                    break
                }
                return .none
                
            case let .locationPermissionRequestFinished(status):
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    state.locationPermissionDenied = false
                    return .send(.startListeningToLocation)
                case .denied, .restricted:
                    state.locationPermissionDenied = true
                    return .none
                case .notDetermined:
                    return .none
                @unknown default:
                    return .none
                }
                
            case .apiKeyLinkTapped:
                state.destination = .apiKeyAlert(ApiKeyAlertFeature.State())
                return .none
                
            case .onSettingsButtonTapped:
                state.destination = .userSettings(UserSettingsFeature.State())
                return .none
                
            case .stopsList:
                return .none
                
            case let .search(.delegate(.stationTapped(station))):
                state.path.append(SearchedStationFeature.State(station: station))
                return .none
                
            case .search:
                return .none
                
            case .destination(.presented(.apiKeyAlert(.delegate(.dismiss)))):
                state.destination = nil
                return .none
                
            case .destination:
                return .none
                
            case .path:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path) {
            SearchedStationFeature()
        }
        
        Scope(state: \.stopsList, action: \.stopsList) {
            StopsListFeature()
        }
        Scope(state: \.search, action: \.search) {
            StopSearchFeature()
        }
    }
}

extension SingleStopFeature {
    @Reducer
    enum Destination {
        case apiKeyAlert(ApiKeyAlertFeature)
        case userSettings(UserSettingsFeature)
    }
}

extension SingleStopFeature.Destination.State: Equatable {}
extension SingleStopFeature.Destination.Action: Equatable {}


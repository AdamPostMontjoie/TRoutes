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
        var hasActiveJourney = false
        var displayCoordinates: CLLocationCoordinate2D?
        var nearbySearchCoordinates: CLLocationCoordinate2D?
    }
    
    enum Action: Equatable {
        case onAppear
        case apiKeyLinkTapped
        case onSettingsButtonTapped
        case requestLocationTapped
        
        case startListeningToLocation
        case startListeningToJourneyUpdates
        case locationAuthorizationStatusReceived(CLAuthorizationStatus)
        case locationPermissionRequestFinished(CLAuthorizationStatus)
        case locationUpdateReceived(NearbyStopsUpdate)
        case journeyUpdateReceived(JourneyUpdate)

        case stopLiveActivityRequested(StopLiveActivityRequest)
        case stopLiveActivityAuthorizationReceived(StopLiveActivityRequest, CLAuthorizationStatus)
        case stopLiveActivityResponse(StopLiveActivityError?)
        
        case stopsList(StopsListFeature.Action)
        case search(StopSearchFeature.Action)
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<SearchedStationFeature>)

        enum Alert: Equatable {
            case openSettings
        }
    }
    
    @Dependency(\.nearbyStopsClient) var nearbyStopsClient
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.stopLiveActivityClient) var stopLiveActivityClient

    private enum CancelID { case journeyUpdates }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let getAuth = nearbyStopsClient.getCurrentAuthorization
                return .merge(
                    .run { send in
                        let status = await getAuth()
                        await send(.locationAuthorizationStatusReceived(status))
                        await send(.startListeningToLocation)
                    },
                    .send(.startListeningToJourneyUpdates)
                )
                
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

            case .startListeningToJourneyUpdates:
                let makeStream = journeyClient.makeJourneyUpdateStream
                return .run { send in
                    for await update in await makeStream() {
                        await send(.journeyUpdateReceived(update))
                    }
                }
                .cancellable(id: CancelID.journeyUpdates, cancelInFlight: true)

            case let .journeyUpdateReceived(update):
                switch update {
                case let .activeJourneyChanged(journey):
                    state.hasActiveJourney = journey != nil
                case .journeyTerminated:
                    state.hasActiveJourney = false
                }
                return .none
                
            case let .locationUpdateReceived(update):
                switch update {
                case .displayCoordinates(let coordinates):
                    state.locationPermissionDenied = false
                    state.displayCoordinates = coordinates
                    return .send(.stopsList(.displayCoordinatesUpdated(coordinates)))
                case .searchCoordinates(let coordinates):
                    state.locationPermissionDenied = false
                    state.nearbySearchCoordinates = coordinates
                    return .send(.stopsList(.fetchNearby(
                        latitude: coordinates.latitude,
                        longitude: coordinates.longitude
                    )))
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

            case let .stopsList(.delegate(.liveActivityRequested(request))):
                return .send(.stopLiveActivityRequested(request))

            case let .path(.element(id: _, action: .delegate(.liveActivityRequested(request)))):
                return .send(.stopLiveActivityRequested(request))

            case let .stopLiveActivityRequested(request):
                guard !state.hasActiveJourney else {
                    state.destination = .alert(.journeyInProgress)
                    return .none
                }
                let getAuthorization = nearbyStopsClient.getCurrentAuthorization
                return .run { send in
                    await send(.stopLiveActivityAuthorizationReceived(
                        request,
                        await getAuthorization()
                    ))
                }

            case let .stopLiveActivityAuthorizationReceived(request, status):
                guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                    state.destination = .alert(.locationRequired)
                    return .none
                }
                let start = stopLiveActivityClient.start
                return .run { send in
                    do {
                        try await start(request)
                        await send(.stopLiveActivityResponse(nil))
                    } catch let error as StopLiveActivityError {
                        await send(.stopLiveActivityResponse(error))
                    } catch {
                        await send(.stopLiveActivityResponse(.requestFailed))
                    }
                }

            case let .stopLiveActivityResponse(error):
                switch error {
                case .activitiesDisabled:
                    state.destination = .alert(.activitiesDisabled)
                case .locationUnavailable:
                    state.destination = .alert(.locationRequired)
                case .requestFailed:
                    state.destination = .alert(.requestFailed)
                case nil:
                    break
                }
                return .none
                
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

            case .destination(.presented(.alert(.openSettings))):
                let openSettings = nearbyStopsClient.openSettings
                return .run { _ in openSettings() }
                
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
        case alert(AlertState<SingleStopFeature.Action.Alert>)
    }
}

extension SingleStopFeature.Destination.State: Equatable {}
extension SingleStopFeature.Destination.Action: Equatable {}

private extension AlertState where Action == SingleStopFeature.Action.Alert {
    static var journeyInProgress: Self {
        Self {
            TextState("Journey in Progress")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState("End your active journey before launching a stop Live Activity.")
        }
    }

    static var locationRequired: Self {
        Self {
            TextState("Location Required")
        } actions: {
            ButtonState(action: .openSettings) { TextState("Open Settings") }
            ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
            TextState("Enable location access before launching a stop Live Activity.")
        }
    }

    static var activitiesDisabled: Self {
        Self {
            TextState("Live Activities Disabled")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState("Enable Live Activities for T Routes in Settings and try again.")
        }
    }

    static var requestFailed: Self {
        Self {
            TextState("Could Not Start Live Activity")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState("Please try again.")
        }
    }
}


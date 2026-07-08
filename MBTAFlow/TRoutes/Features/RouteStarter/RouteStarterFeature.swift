//
//  RouteStarterFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import CoreLocation
import Dependencies
import Foundation

@Reducer
struct RouteStarterFeature {
    @ObservableState
    struct State: Equatable {
        var activeJourneyDisplay: ActiveJourneyDisplayFeature.State {
            get {
                ActiveJourneyDisplayFeature.State(journey: activeJourney)
            }
            set {
                // Intentionally blank to satisfy WritableKeyPath requirement
                // without allowing child mutations.
            }
        }
        var debugDashboardDisplay:DebugDashboardFeature.State {
            get {
                DebugDashboardFeature.State(journey: activeJourney)
            }
            set {
                // Intentionally blank to satisfy WritableKeyPath requirement
                // without allowing child mutations.
            }
        }
        var routeSelector = SelectorFeature.State()
        var isActiveJourneyPresented = false
        var activeJourney: JourneyState?
        var isDebugAvailable = DebugAvailability.current
        @Shared(.isDebugEnabled) var isDebugEnabled = true
        // Holds route while user tries to setup location permissions.
        var pendingRoute: ResolvedUserRoute?
        
        @Presents var destination: Destination.State?

        var isDebugActive: Bool {
            isDebugAvailable && isDebugEnabled
        }
    }
    
    enum Action: Equatable {
        case activeJourneyDisplay(ActiveJourneyDisplayFeature.Action)
        case debugDashboardDisplay(DebugDashboardFeature.Action)
        case onCreateButtonTapped
        case onSettingsButtonTapped
        case routeSelector(SelectorFeature.Action)
        
        // Setup actions
        case startRouteRequested(ResolvedUserRoute)
        case locationAuthorizationStatusReceived(ResolvedUserRoute, CLAuthorizationStatus)
        case locationPermissionRequestFinished(CLAuthorizationStatus)
        case beginRoute(ResolvedUserRoute)
        case endRoute
        
        case destination(PresentationAction<Destination.Action>)
        
        case journeyUpdateReceived(JourneyUpdate)
    }
    
    @Dependency(\.journeyClient) var journeyClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.liveActivityClient) var liveActivityClient
    
    var body: some ReducerOf<Self> {
        Scope(state: \.activeJourneyDisplay, action: \.activeJourneyDisplay) {
            ActiveJourneyDisplayFeature()
        }
        Scope(state: \.debugDashboardDisplay, action: \.debugDashboardDisplay) {
            DebugDashboardFeature()
        }
        Scope(state: \.routeSelector, action: \.routeSelector) {
            SelectorFeature()
        }
        Reduce { state, action in
            switch action {
            case .onCreateButtonTapped:
                state.destination = .createRoute(CreateRouteFeature.State())
                return .none
            case .onSettingsButtonTapped:
                state.destination = .userSettings(UserSettingsFeature.State())
                return .none
            case .destination(.presented(.createRoute(.delegate(.routeSaved)))):
                state.destination = nil
                return .send(.routeSelector(.fetchRoutesFromDisk))

            case .destination(.presented(.createRoute(.delegate(.dismiss)))):
                state.destination = nil
                return .none

            case .activeJourneyDisplay(.delegate(.cancelRoute)):
                return .send(.endRoute)

            case .activeJourneyDisplay(.delegate(.manualAtStop)):
                let atStop = journeyClient.atStop
                return .run { _ in
                    await atStop()
                }

            case .activeJourneyDisplay(.delegate(.manualNextStop)):
                let nextStop = journeyClient.nextStop
                return .run { _ in
                    await nextStop()
                }

            case .activeJourneyDisplay(.delegate(.refreshTimes)):
                let requestNewTimes = journeyClient.requestNewTimes
                return .run { _ in
                    await requestNewTimes()
                }
                
            case .activeJourneyDisplay(.delegate(.confirmedBoarded)):
                let confirmBoarded = journeyClient.confirmBoarded
                return .run { _ in
                    await confirmBoarded()
                }
                
            case .activeJourneyDisplay(.delegate(.confirmedMissed)):
                let confirmMissed = journeyClient.confirmMissed
                return .run { _ in
                    await confirmMissed()
                }

            // This starts the route from inside the app; permission flow remains here.
            case let .routeSelector(.delegate(.startRoute(id))):
                guard let selectedRoute = state.routeSelector.userRoutes.first(where: { $0.id == id }) else {
                    return .none
                }
                return .send(.startRouteRequested(selectedRoute))
            
            case let .startRouteRequested(route):
                let getCurrentAuthorization = journeyClient.getCurrentAuthorization
                return .run { send in
                    let status = await getCurrentAuthorization()
                    await send(.locationAuthorizationStatusReceived(route, status))
                }
            
            case let .locationAuthorizationStatusReceived(route, status):
                print(status.rawValue)
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    return .send(.beginRoute(route))

                case .notDetermined:
                    state.pendingRoute = route
                    state.destination = .locationAlert(LocationAlertFeature.State(mode: .firstTime))
                    return .none
                    
                case .denied, .restricted:
                    state.destination = .locationAlert(LocationAlertFeature.State(mode: .changeSettings))
                    return .none
                @unknown default:
                    return .none
                }

            case let .locationPermissionRequestFinished(status):
                guard let pendingRoute = state.pendingRoute else { return .none }

                switch status {
                case .authorizedAlways, .authorizedWhenInUse:
                    state.pendingRoute = nil
                    return .send(.beginRoute(pendingRoute))

                case .denied, .restricted:
                    state.destination = .locationAlert(.init(mode: .changeSettings))
                    return .none

                case .notDetermined:
                    return .none

                @unknown default:
                    state.pendingRoute = nil
                    return .none
                }
            
            case .destination(.presented(.locationAlert(.delegate(.requestPermissionsInApp)))):
                state.destination = nil
                let requestLocationPermissions = journeyClient.requestLocationAuthorization
                let requestNotificationPermissions = notificationsClient.requestAuthorization
                let getCurrentStatus = journeyClient.getCurrentAuthorization
                return .run { send in
                    await requestLocationPermissions()
                    await requestNotificationPermissions()
                    let status = await getCurrentStatus()
                    await send(.locationPermissionRequestFinished(status))
                }

            case .destination(.presented(.locationAlert(.delegate(.openSettings)))):
                let openSettings = journeyClient.openSettings
                state.destination = nil
                return .run { _ in
                    openSettings()
                }

            case .destination(.presented(.locationAlert(.delegate(.cancel)))):
                state.destination = nil
                state.pendingRoute = nil
                return .none
            
            case let .beginRoute(route):
                let beginRoute = journeyClient.beginRoute
                return .run { send in
                    let stream = await beginRoute(route)
                    for await update in stream {
                        await send(.journeyUpdateReceived(update))
                    }
                }

            case let .journeyUpdateReceived(update):
                switch update {
                case let .activeJourneyChanged(journey):
                    state.activeJourney = journey
                    state.isActiveJourneyPresented = journey != nil
                case let .journeyTerminated(reason):
                    if reason == .locationAuthorizationDenied {
                        state.destination = .locationAlert(.init(mode: .routeInterrupted))
                    }
                    return .none
                }
                return .none

            case .endRoute:
                let endRoute = journeyClient.endRoute
                return .run { _ in
                    await endRoute()
                }

            case .activeJourneyDisplay, .debugDashboardDisplay, .routeSelector, .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RouteStarterFeature {
    @Reducer
    enum Destination {
        case createRoute(CreateRouteFeature)
        case userSettings(UserSettingsFeature)
        case locationAlert(LocationAlertFeature)
    }
}

extension RouteStarterFeature.Destination.State: Equatable {}
extension RouteStarterFeature.Destination.Action: Equatable {}

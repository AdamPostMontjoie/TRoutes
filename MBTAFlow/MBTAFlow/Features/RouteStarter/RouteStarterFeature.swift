//
//  RouteStarterFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation
import Dependencies
import CoreLocation

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
        var routeSelector = SelectorFeature.State()
        var isActiveJourneyPresented = false
        var activeJourney:JourneyState?
        //holds route while user tries to setup location permissions
        var pendingRoute:RouteStruct?
        
        @Presents var destination: Destination.State?
    }
    
    enum Action:Equatable {
        case activeJourneyDisplay(ActiveJourneyDisplayFeature.Action)
        case onCreateButtonTapped
        case routeSelector(SelectorFeature.Action)
        
        //setup actions
        case startRouteRequested(RouteStruct)
        case locationAuthorizationStatusReceived(RouteStruct, CLAuthorizationStatus)
        
        case locationPermissionRequestFinished(CLAuthorizationStatus)
        
        case beginRoute(RouteStruct)
        case fetchPredictions(Stop)
        case endRoute
        
        case destination(PresentationAction<Destination.Action>)
        enum Alert: Equatable {
                    // e.g., case rateLimitAcknowledged
                    // e.g., case openSettingsTapped
        }
        
        // manual widget actions
        case refreshRoutes
        case forcedArrival //at stop button, bypasses region did enter
        case forcedDeparture // next stop button, bypasses region did exit
        
        
        case locationUpdateReceived(LocationEvent)
        case mbtaApiResponseReceived([String])
        
        //handlers for the possible location events
        //we may want to take in stop id and compare to avoid any cases with erroneously saved stuff
        case enteredStop
        case exitedStop
        case authorizationDenied
        case locationError
        
    
        case apiFailed(MBTAError)
        
    }
    
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.liveActivityClient) var liveActivityClient
    @Dependency(\.mbtaClient) var mbtaClient
    var body: some ReducerOf<Self> {
        Scope(state: \.activeJourneyDisplay, action: \.activeJourneyDisplay) {
            ActiveJourneyDisplayFeature()
        }
        Scope(state: \.routeSelector, action: \.routeSelector) {
            SelectorFeature()
        }
        Reduce { state, action in
            switch action {
            
            case .onCreateButtonTapped:
                state.destination = .createRoute(CreateRouteFeature.State())
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
                return .send(.enteredStop)
            case .activeJourneyDisplay(.delegate(.manualNextStop)):
                return .send(.exitedStop)
            //this starts the route from inside the app, most of the logic is kicked off here
            case let .routeSelector(.delegate(.startRoute(id))):
                
                
                guard let selectedRoute = state.routeSelector.userRoutes.first(where: { $0.id == id}) else {
                    return .none
                }
                return .send(.startRouteRequested(selectedRoute))
            
            //all start requests enter here
            case let .startRouteRequested(route):
                let status = locationClient.getCurrentAuthorization()
                return .send(.locationAuthorizationStatusReceived(route, status))
            
            //initial status check
            case let .locationAuthorizationStatusReceived(route, status):
                print(status.rawValue)
                switch status {
                case .authorizedAlways:
                    return .send(.beginRoute(route))

                case .notDetermined:
                    state.pendingRoute = route
                    state.destination = .locationAlert(LocationAlertFeature.State(mode: .firstTime))
                    return .none
                    
                //user doesn't have enough permissions
                case .denied, .restricted, .authorizedWhenInUse:
                    state.destination = .locationAlert(LocationAlertFeature.State(mode: .changeSettings))
                    return .none

                @unknown default:
                    return .none
                }
            case let .locationPermissionRequestFinished(status):
                guard let pendingRoute = state.pendingRoute else { return .none }

                switch status {
                case .authorizedAlways:
                    state.pendingRoute = nil
                    return .send(.beginRoute(pendingRoute))

                case .denied, .restricted, .authorizedWhenInUse:
                    // may need to remove depending on HIG about immediately telling them to change settings
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
                let requestPermissions = locationClient.requestLocationAuthorization
                let getCurrentStatus = locationClient.getCurrentAuthorization
                return .run { send in
                    await requestPermissions()
                    let status = getCurrentStatus()
                    await send(.locationPermissionRequestFinished(status))
                }
            case .destination(.presented(.locationAlert(.delegate(.openSettings)))):
                let openSettings = locationClient.openSettings
                state.destination = nil
                return .run { send in
                    openSettings()
                }
            case .destination(.presented(.locationAlert(.delegate(.cancel)))):
                state.destination = nil
                state.pendingRoute = nil
                return .none
            
            // starts the route
            case let .beginRoute(route):
                let journey = JourneyState(route: route)
                guard let firstStop = journey.currentStop else {
                    return .none
                }

                state.isActiveJourneyPresented = true
                state.activeJourney = journey
               // state.activeJourneyDisplay.journey = state.activeJourney
                
                let startMonitoring = locationClient.startMonitoring
                return .run { send in
                    await send(.fetchPredictions(firstStop))
                    
                    guard let stream = try await startMonitoring() else { return }
                    
                    // Listen to the GPS (Wait at the pipe)
                    // This loop runs infinitely in the background until the effect is cancelled
                    for await location in stream{
                        await send(.locationUpdateReceived(location))
                    }
                }
            //this will be called on natural end or forceful cancelation
            case .endRoute:
                print("end route")
                state.isActiveJourneyPresented = false
                state.activeJourney = nil
                let stopMonitoring = locationClient.stopMonitoring
                return .run { send in
                    try await stopMonitoring()
                }
            case let .fetchPredictions(stop):
                //we should probably clear all predictions instead of fetching new if en route to certain stops
                let fetchTransitTimes = mbtaClient.fetchTransitTimes
                return .run { send in
                    do {
                        let times = try await fetchTransitTimes(stop)
                        // Send the data back into the reducer
                        print(times)
                        await send(.mbtaApiResponseReceived(times))
                    }
                    catch {
                        let mbtaError = error as? MBTAError ?? .networkError
                        await send(.apiFailed(mbtaError))
                    }
                }.cancellable(id: CancelID.apiFetch, cancelInFlight: true)
            case let .mbtaApiResponseReceived(upcomingTimes):
               
                state.activeJourney?.activePredictionTimes = upcomingTimes
                if upcomingTimes.isEmpty {
                    state.activeJourney? .needTimes = false
                }
                
                return .none
             //   state.activeRouteDisplay.journey = state.activeJourney
               
            case .refreshRoutes:
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                return .send(.fetchPredictions(currentStop))
            //these will tell the location client it's time to force switch regions or whatever
            //location client will then send locationEvent into stream
            case .forcedArrival:
                return .send(.enteredStop)
            case .forcedDeparture:
                return .send(.exitedStop)
            //determine what the location event actually was
            //send the action that corresponds to that update.
            //those actions will update the state to correspond
            case let .locationUpdateReceived(locationEvent):
                switch locationEvent {
                case .enteredStop:
                    return .send(.enteredStop)
                case .exitedStop:
                    return .send(.exitedStop)
                case .authorizationDenied:
                    return .send(.authorizationDenied)
                case .monitoringFailed:
                    return .send(.locationError)
                }
            //handles what to do with state when user arrives at stop
            case .enteredStop:
                //ignore if already at stop
                guard state.activeJourney?.movementStatus == .enRoute else { return .none }
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                switch currentStop.stopType {
                case .transferStop:
                    //run effect
                   
                    guard let newStop = state.activeJourney?.advanceToNextStop() else {
                        return .none
                    }
                    //if they overlap, we're already at the next stop. if not, user is en route to the next stop
                    if currentStop.overlapsWithNext {
                        state.activeJourney?.movementStatus = .atStop
                    } else {
                        state.activeJourney?.movementStatus = .enRoute
                    }
                    state.activeJourney?.needTimes = true
                    let registerNextStopRegion = locationClient.registerNextStopRegion
                    return .run { send in
                        try await registerNextStopRegion(newStop)
                        //get times for the new stop
                        await send(.fetchPredictions(newStop))
                    }
                    //fire did exit as either way, we're dropping bounds
                case .boardingStop:
                    //get new times, don't update current stop
                    state.activeJourney?.movementStatus = .atStop
                    state.activeJourney?.needTimes = true
                    
                    return .send(.fetchPredictions(currentStop))
                    
                case .finalStop:
                    //user can dismiss via widget or leaving
                    state.activeJourney?.movementStatus = .atStop
                    return .none
                }
            case .exitedStop:
                guard let currentStop = state.activeJourney?.currentStop else {
                    return .none
                }
                switch currentStop.stopType {
                case .transferStop:
                    //this probably shouldn't happen? we should have already dropped monitoring here
                    return .none
                case .boardingStop:
                    state.activeJourney?.movementStatus = .enRoute
                    state.activeJourney?.stopIndex += 1
                    guard let newStop = state.activeJourney?.currentStop else {
                        return .none
                    }
                    //we're on way to transfer or final stop, need no new times
                    state.activeJourney?.activePredictionTimes = []
                    state.activeJourney?.needTimes = false
                    let registerNextStopRegion = locationClient.registerNextStopRegion
                    return .run { send in
                        try await registerNextStopRegion(newStop)
                        //we probably don't need predictions, because next stop with be transfer or final
                      //  await send(.fetchPredictions(newStop))
                    }
                case .finalStop:
                    //kill route if they wander off
                    return .send(.endRoute)
                }
            //kill the route, tell the user to navigate to settings
            case .authorizationDenied:
                return .run { send in
                    await send(.endRoute)
                    // send alert that tells the user they have to go to settings
                    // this should also display if they try and hit start while it's disabled every time
                    print("User must enable location services in settings")
                    // add a link/way for the user to navigate to settings page
                }
            case .locationError:
                return .none
            case let .apiFailed(error):
                switch error {
                //need disruptive alert
                case .rateLimited:
                    print("rate limited")
                case .networkError, .timeoutError:
                    state.activeJourney?.warningMessage = "Cannot reach times"
                case .serverError:
                    state.activeJourney?.warningMessage = "MBTA Server Issue"
                default:
                // For Developer Errors (Decoding, Bad Request, Forbidden)
                    state.activeJourney?.warningMessage = "Data Unavailable"
                }
                
                state.activeJourney?.needTimes = false
                return .none
            //does nothing
            case .activeJourneyDisplay, .routeSelector, .destination:
                return .none
           
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RouteStarterFeature {
    @Reducer
    enum Destination {
        // Standard TCA Alert (for rate limits, timeouts, etc.)
        case alert(AlertState<RouteStarterFeature.Action.Alert>)
        case createRoute(CreateRouteFeature)
        case locationAlert(LocationAlertFeature)
    }
}

extension RouteStarterFeature.Destination.State: Equatable {}
extension RouteStarterFeature.Destination.Action: Equatable {}

private enum CancelID { case apiFetch }

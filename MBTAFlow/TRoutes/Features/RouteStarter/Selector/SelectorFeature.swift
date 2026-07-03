//
//  SelectorFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct SelectorFeature {
    

    @ObservableState
    struct State: Equatable {
        var userRoutes: IdentifiedArrayOf<UserRoute> = []
        var path = StackState<RouteReviewFeature.State>()
        @Presents var destination: Destination.State? // Added
    }

    enum Action: Equatable {
        case selected
        case path(StackAction<RouteReviewFeature.State, RouteReviewFeature.Action>)
        case fetchRoutesFromDisk
        case deleteRouteFromDisk(UUID)
        case routesFetched([UserRoute])
        case fetchRoutesFailed
        //we need to implement the deletion and editing here and in the routereviewfeature
        //both behavior and the alerts should be the same
        //modularize?
        case deleteButtonTapped(UUID)
        case editButtonTapped
        case startButtonTapped(UUID)
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        enum Alert: Equatable {
            case confirmDelete(UUID)
        }
        
        enum Delegate: Equatable {
            case startRoute(UUID)
        }
    }

    @Dependency(\.mbtaClient) var mbtaClient: MBTAClient
    @Dependency(\.databaseClient) var databaseClient: DatabaseClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selected:
                return .none
            
            case let .path(.element(id: _, action: .delegate(.updateRoute(route)))):
                let updateRoute = databaseClient.updateRoute
                return .run { send in
                    do {
                        try await updateRoute(route)
                        await send(.fetchRoutesFromDisk)
                    } catch {
                        //update routes failed
                        await send(.fetchRoutesFailed)
                    }
                }
            case .fetchRoutesFromDisk:
                let fetchSavedRoutes = databaseClient.fetchSavedRoutes
                return .run { send in
                    do {
                        let routes = try await fetchSavedRoutes()
                        await send(.routesFetched(routes))
                    } catch {
                        await send(.fetchRoutesFailed)
                    }
                }

            case let .deleteRouteFromDisk(routeId):
                let deleteRoute = databaseClient.deleteRoute
                return .run { send in
                    do {
                        try await deleteRoute(routeId)
                        await send(.fetchRoutesFromDisk)
                    } catch {
                        await send(.fetchRoutesFailed)
                    }
                }

            case let .routesFetched(routes):
                state.userRoutes = IdentifiedArray(uniqueElements: routes)
                return .none

            case .fetchRoutesFailed:
                return .none

            case let .startButtonTapped(route):
                return .send(.delegate(.startRoute(route)))

            case .editButtonTapped:
                return .none

            case let .deleteButtonTapped(routeId):
                state.destination = .alert(.confirmDelete(routeId: routeId))
                return .none

            case let .destination(.presented(.alert(.confirmDelete(routeId)))):
                return .send(.deleteRouteFromDisk(routeId))

            case .destination, .path, .delegate:
                return .none

            }
        }
        .forEach(\.path, action: \.path) {
            RouteReviewFeature()
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension SelectorFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<SelectorFeature.Action.Alert>)
    }
}

extension SelectorFeature.Destination.State: Equatable {}
extension SelectorFeature.Destination.Action: Equatable {}

extension AlertState where Action == SelectorFeature.Action.Alert {
    static func confirmDelete(routeId: UUID) -> Self {
        Self {
            TextState("Delete Route?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete(routeId)) {
                TextState("Delete")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState("Are you sure you want to permanently delete this route?")
        }
    }
}

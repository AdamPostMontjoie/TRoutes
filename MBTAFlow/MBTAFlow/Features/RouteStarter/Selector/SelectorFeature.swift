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
        var userRoutes: IdentifiedArrayOf<RouteStruct> = [
            RouteStruct(
                stops: [
                    Stop(stopName: "Alewife", longitude: "-71.1429", latitude: "42.3954", lastStop: false, address: "123 Seasame Street"),
                    Stop(stopName: "South Station", longitude: "-71.0552", latitude: "42.3523", lastStop: true,address: "123 Seasame Street")
                ],
                routeId: UUID(),
                name: "Morning Red Line",
                timeStamp: Date()
            ),
            RouteStruct(
                stops: [
                    Stop(stopName: "Oak Grove", longitude: "-71.0711", latitude: "42.4367", lastStop: false,address: "123 Seasame Street"),
                    Stop(stopName: "Back Bay", longitude: "-71.0757", latitude: "42.3473", lastStop: true,address: "123 Seasame Street")
                ],
                routeId: UUID(),
                name: "Orange Line Commute",
                timeStamp: Date()
            )
        ]
        var path = StackState<RouteReviewFeature.State>()
    }
    
    enum Action: Equatable {
        case selected
        case path(StackAction<RouteReviewFeature.State, RouteReviewFeature.Action>)
        case alert
        //we need to implement the deletion and editing here and in the routereviewfeature
        //both behavior and the alerts should be the same
        //modularize?
        case deleteButtonTapped
        case editButtonTapped
        case startButtonTapped(UUID)
        case delegate(Delegate)
        enum Delegate:Equatable
        {
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
            case let .startButtonTapped(id):
                
                return .send(.delegate(.startRoute(id)))
            case .editButtonTapped:
                return .none
            case .deleteButtonTapped:
                return .none
            case .path:
                return .none
            case .alert:
                return .none
            case .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            RouteReviewFeature()
        }
    }
}

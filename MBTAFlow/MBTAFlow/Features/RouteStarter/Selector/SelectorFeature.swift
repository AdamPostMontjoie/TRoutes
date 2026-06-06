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
                legs: [
                    Leg(
                        startStop: Stop(
                            id: UUID(),
                            mbtaStopId: "place-alfcl",
                            mbtaRouteId: "Red",
                            stopName: "Alewife",
                            longitude: -71.1429,
                            latitude: 42.3954,
                            lastStop: false,
                            address: "Alewife Brook Parkway, Cambridge, MA"
                        ),
                        endStop: Stop(
                            id: UUID(),
                            mbtaStopId: "place-sstat",
                            mbtaRouteId: "Red",
                            stopName: "South Station",
                            longitude: -71.0552,
                            latitude: 42.3523,
                            lastStop: true,
                            address: "700 Atlantic Ave, Boston, MA"
                        ),
                        mbtaRouteId: "Red",
                        transitType: .redLine
                    )
                ],
                id: UUID(),
                name: "Morning Red Line",
                timeStamp: Date()
            ),
            RouteStruct(
                legs: [
                    Leg(
                        startStop: Stop(
                            id: UUID(),
                            mbtaStopId: "place-ogmnl",
                            mbtaRouteId: "Orange",
                            stopName: "Oak Grove",
                            longitude: -71.0711,
                            latitude: 42.4367,
                            lastStop: false,
                            address: "Washington St, Malden, MA"
                        ),
                        endStop: Stop(
                            id: UUID(),
                            mbtaStopId: "place-bbsta",
                            mbtaRouteId: "Orange",
                            stopName: "Back Bay",
                            longitude: -71.0757,
                            latitude: 42.3473,
                            lastStop: true,
                            address: "145 Dartmouth St, Boston, MA"
                        ),
                        mbtaRouteId: "Orange",
                        transitType: .orangeLine
                    )
                ],
                id: UUID(),
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

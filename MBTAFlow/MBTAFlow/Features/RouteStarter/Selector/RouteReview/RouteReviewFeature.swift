//
//  RouteReviewFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct RouteReviewFeature {
    @ObservableState
    struct State: Equatable {
        var route: RouteStruct
        var stops: IdentifiedArrayOf<StopRowFeature.State> = []
        init(route: RouteStruct) {
                self.route = route
                self.stops = IdentifiedArray(
                    uniqueElements: route.stops.map { StopRowFeature.State(stop: $0) }
                )
            }
    }

    enum Action: Equatable {
        //may want to modularize, shared behavior with selectorfeature
        case editNameButtonTapped(String)
        case deleteRouteButtonTapped //displays alert for confirmation
        case delegate(Delegate)
        case stops(IdentifiedActionOf<StopRowFeature>)
        enum Delegate: Equatable {
            case deleteRoute(UUID)
            case updateRoute(RouteStruct) //change to route updated? we can reuse on stop deletion from child reducer
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .editNameButtonTapped(newName): //maybe change action name to deselected for accuracy
                state.route.name = newName
                                // Tell the parent to update the master array and save to db
                return .send(.delegate(.updateRoute(state.route)))
            case .deleteRouteButtonTapped:
                //pop from stack
                return .send(.delegate(.deleteRoute(state.route.routeId)))
            case let .stops(.element(id: childId, action: .delegate(.deleteStop))):
                state.route.stops.removeAll { $0.id == childId }
                return .send(.delegate(.updateRoute(state.route)))
                            
            case let .stops(.element(id:childId, action: .delegate(.stopUpdated(newStop)))):
                //find and replace the stop locally
                if let index = state.route.stops.firstIndex(where: { $0.id == childId}) {
                    state.route.stops[index] = newStop
                }
                return .send(.delegate(.updateRoute(state.route)))
            case .delegate:
                return .none
            case .stops:
                return .none
            }
        }
        .forEach(\.stops, action: \.stops) {
                    StopRowFeature()
        }
    }
}

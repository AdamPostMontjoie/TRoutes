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
                    uniqueElements: route.legs.flatMap { leg in
                        [
                            StopRowFeature.State(stop: leg.startStop),
                            StopRowFeature.State(stop: leg.endStop)
                        ]
                    }
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
                return .send(.delegate(.deleteRoute(state.route.id)))
            case let .stops(.element(id: childId, action: .delegate(.deleteStop))):
                state.route.legs.removeAll {
                    $0.startStop.id == childId || $0.endStop.id == childId
                }
                state.stops.remove(id: childId)
                return .send(.delegate(.updateRoute(state.route)))
                            
            case let .stops(.element(id: childId, action: .delegate(.stopUpdated(newStop)))):
                for index in state.route.legs.indices {
                    if state.route.legs[index].startStop.id == childId {
                        state.route.legs[index].startStop = newStop
                    }
                    if state.route.legs[index].endStop.id == childId {
                        state.route.legs[index].endStop = newStop
                    }
                }
                state.stops[id: childId]?.stop = newStop
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

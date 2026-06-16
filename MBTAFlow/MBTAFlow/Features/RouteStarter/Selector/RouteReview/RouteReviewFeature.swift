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
    private func defaultRouteName(for legs: [Leg]) -> String? {
        guard let firstLeg = legs.first,
              let lastLeg = legs.last else {
            return nil
        }

        return "\(firstLeg.startStop.stopName) to \(lastLeg.endStop.stopName)"
    }
    //renames routes if they're default and stops have changed, does not if customizing or customized
    private func routeWithUpdatedDefaultName(previousRoute: RouteStruct?, updatedRoute: RouteStruct) -> RouteStruct {
        guard let previousRoute,
              previousRoute.name == defaultRouteName(for: previousRoute.legs),
              updatedRoute.name == previousRoute.name,
              let updatedDefaultName = defaultRouteName(for: updatedRoute.legs) else {
            return updatedRoute
        }

        var route = updatedRoute
        route.name = updatedDefaultName
        return route
    }
    @ObservableState
    struct State: Equatable {
        var route: RouteStruct
        var legRows: IdentifiedArrayOf<LegRowFeature.State> = []
        @Presents var destination: Destination.State?

        init(route: RouteStruct) {
            self.route = route
            self.legRows = IdentifiedArray(
                uniqueElements: route.legs.map { LegRowFeature.State(leg: $0) }
            )
        }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case nameEditingEnded
        case deleteRouteButtonTapped
        case addLegButtonTapped
        case delegate(Delegate)
        case legRows(IdentifiedActionOf<LegRowFeature>)
        case destination(PresentationAction<Destination.Action>)

        enum Delegate: Equatable {
            case deleteRoute(UUID)
            case updateRoute(RouteStruct)
        }
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .nameEditingEnded:
                return .send(.delegate(.updateRoute(state.route)))

            case .deleteRouteButtonTapped:
                return .send(.delegate(.deleteRoute(state.route.id)))

            case .addLegButtonTapped:
                state.destination = .addLegs(AddLegsToRouteFeature.State())
                return .none

            case let .legRows(.element(id: _, action: .delegate(.editLeg(leg)))):
                state.destination = .editLeg(EditLegFeature.State(leg: leg))
                return .none
            
            //if this is the last leg, should we delete the entire route?
            case let .legRows(.element(id: _, action: .delegate(.deleteLeg(id)))):
                let previousRoute = state.route
                state.route.legs.removeAll() { $0.id == id }
                state.route = routeWithUpdatedDefaultName(previousRoute: previousRoute, updatedRoute: state.route)
                state.legRows.removeAll() { $0.id == id }
                return .send(.delegate(.updateRoute(state.route)))

            case let .destination(.presented(.editLeg(.delegate(.saveEditedLeg(updatedLeg))))):
                guard let index = state.route.legs.firstIndex(where: { $0.id == updatedLeg.id }) else {
                    return .none
                }

                let previousRoute = state.route
                state.route.legs[index] = updatedLeg
                state.route = routeWithUpdatedDefaultName(previousRoute: previousRoute, updatedRoute: state.route)
                state.legRows = IdentifiedArray(
                    uniqueElements: state.route.legs.map { LegRowFeature.State(leg: $0) }
                )
                return .send(.delegate(.updateRoute(state.route)))

            case let .destination(.presented(.addLegs(.delegate(.appendAddedLegs(newLegs))))):
                guard !newLegs.isEmpty else {
                    return .none
                }

                let previousRoute = state.route
                state.route.legs.append(contentsOf: newLegs)
                state.route = routeWithUpdatedDefaultName(previousRoute: previousRoute, updatedRoute: state.route)
                state.legRows = IdentifiedArray(
                    uniqueElements: state.route.legs.map { LegRowFeature.State(leg: $0) }
                )
                return .send(.delegate(.updateRoute(state.route)))

            case .delegate, .legRows, .destination:
                return .none
            }
        }
        .forEach(\.legRows, action: \.legRows) {
            LegRowFeature()
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RouteReviewFeature {
    @Reducer
    enum Destination {
        case editLeg(EditLegFeature)
        case addLegs(AddLegsToRouteFeature)
    }
}

extension RouteReviewFeature.Destination.State: Equatable {}
extension RouteReviewFeature.Destination.Action: Equatable {}

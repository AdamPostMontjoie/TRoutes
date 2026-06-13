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

            case let .legRows(.element(id: id, action: .editButtonTapped)):
                guard let leg = state.legRows[id: id]?.leg else {
                    return .none
                }
                state.destination = .editLeg(LegFormFeature.State(mode: .edit, leg: leg))
                return .none

            case let .destination(.presented(.editLeg(.delegate(.saveEditedLeg(updatedLeg))))):
                guard let index = state.route.legs.firstIndex(where: { $0.id == updatedLeg.id }) else {
                    return .none
                }

                state.route.legs[index] = updatedLeg
                state.legRows = IdentifiedArray(
                    uniqueElements: state.route.legs.map { LegRowFeature.State(leg: $0) }
                )
                state.destination = nil
                return .send(.delegate(.updateRoute(state.route)))

            case .destination(.presented(.editLeg(.delegate(.requestDismissal)))):
                state.destination = nil
                return .none

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
        case editLeg(LegFormFeature)
    }
}

extension RouteReviewFeature.Destination.State: Equatable {}
extension RouteReviewFeature.Destination.Action: Equatable {}

//
//  LegRowFeature.swift
//  TRoutes
//
//  Created by Adam Post on 6/7/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct LegRowFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID
        var leg: Leg

        init(leg: Leg) {
            self.id = leg.id
            self.leg = leg
        }
    }

    enum Action: Equatable {
        case editButtonTapped
        case deleteButtonTapped
        case delegate(Delegate)
        enum Delegate: Equatable {
            case editLeg(Leg)
            case deleteLeg(UUID)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .deleteButtonTapped:
                return .send(.delegate(.deleteLeg(state.leg.id)))
            case .editButtonTapped:
                return .send(.delegate(.editLeg(state.leg)))
            case .delegate:
                return .none
            }
        }
    }
}

//
//  AddLegsToRouteFeature.swift
//  TRoutes
//
//  Created by Coding Assistant on 6/14/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct AddLegsToRouteFeature {
    @ObservableState
    struct State: Equatable {
        var addedLegs: [Leg] = []
        var pendingAddedLegs: [Leg] = []
        var legForm = LegFormFeature.State(mode: .addToExisting)
        var isSaving = false
        @Presents var destination: Destination.State?
    }

    enum Action: Equatable {
        case legForm(LegFormFeature.Action)
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)

        enum Alert: Equatable {
            case confirmDismiss
            case confirmSave
            case cancelSave
        }

        enum Delegate: Equatable {
            case appendAddedLegs([Leg])
            case dismiss
        }
    }
    @Dependency(\.dismiss) var dismiss
    var body: some ReducerOf<Self> {
        Scope(state: \.legForm, action: \.legForm) {
            LegFormFeature()
        }

        Reduce { state, action in
            switch action {
            case let .legForm(.delegate(.addAnotherLeg(leg))):
                state.addedLegs.append(leg)
                state.legForm = LegFormFeature.State(mode: .addToExisting)
                return .none

            case let .legForm(.delegate(.addLeg(lastLeg))):
                state.pendingAddedLegs = state.addedLegs + [lastLeg]
                state.destination = .alert(.appendLegs(legCount: state.pendingAddedLegs.count))
                return .none

            case .legForm(.delegate(.requestDismissal)):
                if state.addedLegs.isEmpty {
                    state.destination = nil
                    return .run { _ in await self.dismiss() }
                } else {
                    state.destination = .alert(.confirmDismiss())
                    return .none
                }

            case .destination(.presented(.alert(.confirmDismiss))):
                state.addedLegs = []
                state.pendingAddedLegs = []
                state.destination = nil
                return .run { _ in await self.dismiss() }

            case .destination(.presented(.alert(.confirmSave))):
                guard !state.pendingAddedLegs.isEmpty else {
                    return .none
                }

                state.isSaving = true
                let legs = state.pendingAddedLegs
                state.pendingAddedLegs = []
                state.destination = nil
                return .run { send in
                    await send(.delegate(.appendAddedLegs(legs)))
                    await self.dismiss()
                }

            case .destination(.presented(.alert(.cancelSave))):
                state.pendingAddedLegs = []
                return .none

            case .legForm, .destination, .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension AddLegsToRouteFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<AddLegsToRouteFeature.Action.Alert>)
    }
}

extension AddLegsToRouteFeature.Destination.State: Equatable {}
extension AddLegsToRouteFeature.Destination.Action: Equatable {}

extension AlertState where Action == AddLegsToRouteFeature.Action.Alert {
    static func confirmDismiss() -> Self {
        Self {
            TextState("Discard Added Legs?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDismiss) {
                TextState("Discard")
            }
            ButtonState(role: .cancel) {
                TextState("Keep Editing")
            }
        } message: {
            TextState("You have unsaved changes. Are you sure you want to exit?")
        }
    }

    static func appendLegs(legCount: Int) -> Self {
        Self {
            TextState("Add Legs")
        } actions: {
            ButtonState(action: .confirmSave) {
                TextState("Add")
            }
            ButtonState(role: .cancel, action: .cancelSave) {
                TextState("Cancel")
            }
        } message: {
            TextState("Add \(legCount) \(legCount > 1 ? "legs" : "leg") to this route?")
        }
    }
}

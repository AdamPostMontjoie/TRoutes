//
//  EditLegFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/13/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EditLegFeature {
    private func hasMeaningfulChanges(from originalLeg: Leg, to editedLeg: Leg?) -> Bool {
        guard let editedLeg else {
            return true
        }

        return originalLeg.startStop.mbtaStopId != editedLeg.startStop.mbtaStopId
            || originalLeg.endStop.mbtaStopId != editedLeg.endStop.mbtaStopId
            || originalLeg.mbtaRouteId != editedLeg.mbtaRouteId
            || originalLeg.transitType != editedLeg.transitType
            || originalLeg.transitBranch?.id != editedLeg.transitBranch?.id
            || originalLeg.transitDirection?.directionId != editedLeg.transitDirection?.directionId
    }

    @ObservableState
    struct State: Equatable {
        var legForm: LegFormFeature.State
        var pendingEditedLeg: Leg?
        var originalLeg:Leg
        @Presents var destination: Destination.State?

        init(leg: Leg) {
            self.legForm = LegFormFeature.State(mode: .edit, leg: leg)
            self.originalLeg = leg
        }
    }

    enum Action: Equatable {
        case legForm(LegFormFeature.Action)
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)

        enum Alert: Equatable {
            case confirmDismiss
            case confirmSave
            case cancelSave
            case saveFailed
        }

        enum Delegate: Equatable {
            case saveEditedLeg(Leg)
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
            case let .legForm(.delegate(.saveEditedLeg(updatedLeg))):
                guard hasMeaningfulChanges(from: state.originalLeg, to: updatedLeg) else {
                    return .send(.delegate(.dismiss))
                    
                }

                state.pendingEditedLeg = updatedLeg
                state.destination = .alert(.saveEditedLeg())
                return .none

            case .legForm(.delegate(.requestDismissal)):
                guard hasMeaningfulChanges(from: state.originalLeg, to: state.legForm.currentLeg) else {
                    return .run { _ in await self.dismiss() }
                }

                state.destination = .alert(.confirmDismiss())
                return .none

            case .destination(.presented(.alert(.confirmDismiss))):
                state.pendingEditedLeg = nil
                state.destination = nil
                return .run { _ in await self.dismiss() }

            case .destination(.presented(.alert(.confirmSave))):
                guard let updatedLeg = state.pendingEditedLeg else {
                    state.destination = .alert(.saveFailed())
                    return .none
                }

                state.pendingEditedLeg = nil
                    
                return .run { send in
                    await self.dismiss()
                    await send(.delegate(.saveEditedLeg(updatedLeg)))
                }
                
               

            case .destination(.presented(.alert(.cancelSave))):
                state.pendingEditedLeg = nil
                return .none

            case .legForm, .destination, .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension EditLegFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<EditLegFeature.Action.Alert>)
    }
}

extension EditLegFeature.Destination.State: Equatable {}
extension EditLegFeature.Destination.Action: Equatable {}

extension AlertState where Action == EditLegFeature.Action.Alert {
    static func confirmDismiss() -> Self {
        Self {
            TextState("Discard Leg Edits?")
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

    static func saveEditedLeg() -> Self {
        Self {
            TextState("Save Leg Changes")
        } actions: {
            ButtonState(action: .confirmSave) {
                TextState("Save")
            }
            ButtonState(role: .cancel, action: .cancelSave) {
                TextState("Cancel")
            }
        } message: {
            TextState("Save these changes to this leg?")
        }
    }

    static func saveFailed() -> Self {
        Self {
            TextState("Could Not Save Leg")
        } actions: {
            ButtonState(role: .cancel) {
                TextState("OK")
            }
        } message: {
            TextState("Please try again.")
        }
    }
}

//
//  CreateStepFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//
import ComposableArchitecture
import Foundation

@Reducer
struct CreateRouteFeature {
    @ObservableState
    struct State: Equatable {
        // The array holding the finalized segments of the route
        var completedLegs: [Leg] = []
        
        // The active form the user is currently filling out
        var legForm = LegFormFeature.State(mode: .create)
        
        // Presentation state for our confirmation alerts
        @Presents var destination: Destination.State?
    }
    
    enum Action: Equatable {
        // Child feature actions
        case legForm(LegFormFeature.Action)
        
        // Alert actions
        case destination(PresentationAction<Destination.Action>)
        
        case resetForm
        case saveFailed
        
        enum Alert: Equatable {
            case confirmDismiss
            case confirmSave
            case cancelSave
            case saveFailed
        }
        
        // Communication back to RouteStarterFeature
        case delegate(Delegate)
        enum Delegate: Equatable {
            case dismiss
            case routeSaved
        }
    }

    @Dependency(\.databaseClient) var databaseClient
    var body: some ReducerOf<Self> {
        Scope(state: \.legForm, action: \.legForm) {
            LegFormFeature()
        }
        
        Reduce { state, action in
            switch action {
            case let .legForm(.delegate(.addAnotherLeg(newLeg))):
                state.completedLegs.append(newLeg)
                state.legForm = LegFormFeature.State(mode: .create)
                return .none

            case let .legForm(.delegate(.completeRoute(lastLeg))):
                state.completedLegs.append(lastLeg)
                state.destination = .alert(.saveRoute(legCount: state.completedLegs.count))
                return .none

            case .legForm(.delegate(.requestDismissal)):
                if state.completedLegs.isEmpty && state.legForm.selectedType == nil {
                    return .send(.delegate(.dismiss))
                } else {
                    state.destination = .alert(.confirmDismiss())
                    return .none
                }

            case .resetForm:
                state.completedLegs = []
                state.legForm = LegFormFeature.State(mode: .create)
                return .none

            case .destination(.presented(.alert(.confirmDismiss))):
                return .run { send in
                    await send(.resetForm)
                    await send(.delegate(.dismiss))
                }
                
            case .destination(.presented(.alert(.confirmSave))):
                let saveRoute = databaseClient.saveRoute
                return .run { [legs = state.completedLegs] send in
                    do {
                        try await saveRoute(legs)
                        await send(.resetForm)
                        await send(.delegate(.routeSaved))
                    } catch {
                        await send(.saveFailed)
                    }
                }
                
            case .destination(.presented(.alert(.cancelSave))):
                // Pop the leg so the user can modify it in the active form
                if !state.completedLegs.isEmpty {
                    state.completedLegs.removeLast()
                }
                return .none

            case .saveFailed:
                state.destination = .alert(.saveFailed())
                return .none

            case .legForm, .destination, .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension CreateRouteFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<CreateRouteFeature.Action.Alert>)
    }
}

extension CreateRouteFeature.Destination.State: Equatable {}
extension CreateRouteFeature.Destination.Action: Equatable {}

extension AlertState where Action == CreateRouteFeature.Action.Alert {
    static func confirmDismiss() -> Self {
        Self {
            TextState("Discard Route?")
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
    
    static func saveRoute(legCount: Int) -> Self {
        Self {
            TextState("Save Route")
        } actions: {
            ButtonState(action: .confirmSave) {
                TextState("Save")
            }
            ButtonState(role: .cancel, action: .cancelSave) {
                TextState("Cancel")
            }
        } message: {
            TextState("Save this route with \(legCount) \(legCount > 1 ? "segments" : "segment")")
        }
    }

    static func saveFailed() -> Self {
        Self {
            TextState("Could Not Save Route")
        } actions: {
            ButtonState(role: .cancel) {
                TextState("OK")
            }
        } message: {
            TextState("Please try again.")
        }
    }
}

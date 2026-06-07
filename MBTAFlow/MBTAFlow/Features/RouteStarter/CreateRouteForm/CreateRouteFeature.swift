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
        var addLeg = AddLegFeature.State()
        
        // Presentation state for our confirmation alerts
        @Presents var destination: Destination.State?
    }
    
    enum Action: Equatable {
        // Child feature actions
        case addLeg(AddLegFeature.Action)
        
        // Parent UI actions
        case cancelButtonTapped
        case saveRouteButtonTapped
        
        // Alert actions
        case destination(PresentationAction<Destination.Action>)
        
        enum Alert: Equatable {
            case confirmDismiss
            case confirmSave
            case cancelSave
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
        // Scope connects the child reducer to the parent
        Scope(state: \.addLeg, action: \.addLeg) {
            AddLegFeature()
        }
        
        Reduce { state, action in
            switch action {
                
            // 1. Catching the completed leg from the child form
            case let .addLeg(.delegate(.addAnotherLeg(newLeg))):
                // Save the leg to the parent array
                state.completedLegs.append(newLeg)
                
                // THE REFRESH MECHANISM: Overwrite the child state with a fresh initialization.
                // SwiftUI will instantly reset the form back to step 1.
                state.addLeg = AddLegFeature.State()
                return .none
            case let .addLeg(.delegate(.completeRoute(lastLeg))):
                //we instead want to launch alert from here.
                state.completedLegs.append(lastLeg)
                state.destination = .alert(.saveRoute(legCount:state.completedLegs.count))
                return .none
            // 2. Dismissal Logic
            case .cancelButtonTapped:
                // If they haven't done anything, just close it
                if state.completedLegs.isEmpty && state.addLeg.selectedType == nil {
                    return .send(.delegate(.dismiss))
                } else {
                    // If they have unsaved work, show the warning alert
                    state.destination = .alert(.confirmDismiss())
                    return .none
                }
                
            // 3. Saving Logic
            case .saveRouteButtonTapped:
                // Optionally grab the active leg if they forgot to hit "add" before saving
                // (You can implement logic here to validate state.addLeg and append it if it's finished)
                
                state.destination = .alert(.saveRoute(legCount:state.completedLegs.count))
                return .none
                
            // Alert Confirmations
            case .destination(.presented(.alert(.confirmDismiss))):
                return .send(.delegate(.dismiss))
                
            case .destination(.presented(.alert(.confirmSave))):
                // handle database client
                
                //tell the routestarter a new route is added, and swiftdata needs to be called
                
                return .run {[legs = state.completedLegs] send in
                    do {
                        try await databaseClient.saveRoute(legs)
                        await send(.delegate(.routeSaved))
                    } catch {
                        print("fuck")
                    }
                }
                
            case .destination(.presented(.alert(.cancelSave))):
                // Pop the leg so the user can modify it in the active form
                if !state.completedLegs.isEmpty {
                    state.completedLegs.removeLast()
                }
                return .none
            case .addLeg, .destination, .delegate:
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
    
    // Parameterized to receive the active state count
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
}

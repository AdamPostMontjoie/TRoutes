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
        }
        
        // Communication back to RouteStarterFeature
        case delegate(Delegate)
        enum Delegate: Equatable {
            case dismiss
            case routeSaved([Leg]) // Will eventually pass the full RouteStruct
        }
    }
    
    var body: some ReducerOf<Self> {
        // Scope connects the child reducer to the parent
        Scope(state: \.addLeg, action: \.addLeg) {
            AddLegFeature()
        }
        
        Reduce { state, action in
            switch action {
                
            // 1. Catching the completed leg from the child form
            case let .addLeg(.delegate(.submitLeg(newLeg))):
                // Save the leg to the parent array
                state.completedLegs.append(newLeg)
                
                // THE REFRESH MECHANISM: Overwrite the child state with a fresh initialization.
                // SwiftUI will instantly reset the form back to step 1.
                state.addLeg = AddLegFeature.State()
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
                
            // 4. Alert Confirmations
            case .destination(.presented(.alert(.confirmDismiss))):
                return .send(.delegate(.dismiss))
                
            case .destination(.presented(.alert(.confirmSave))):
                // Fire the delegate so RouteStarter can trigger the DatabaseClient
                return .send(.delegate(.routeSaved(state.completedLegs)))
                
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
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState("Save this route with \(legCount) segments?")
        }
    }
}

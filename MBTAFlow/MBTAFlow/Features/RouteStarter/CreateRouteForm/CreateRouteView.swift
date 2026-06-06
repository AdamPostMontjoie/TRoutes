//
//  CreateStepView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct CreateRouteView: View {
    @Bindable var store: StoreOf<CreateRouteFeature>
    
    var body: some View {
        NavigationStack {
            VStack {
                // If they have completed legs, you can show a mini-timeline at the top here later
                if !store.completedLegs.isEmpty {
                    Text("\(store.completedLegs.count) legs added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                
                // Inject the isolated child form
                AddLegView(
                    store: store.scope(
                        state: \.addLeg,
                        action: \.addLeg
                    )
                )
            }
            .navigationTitle(store.completedLegs.isEmpty ? "Create Route" : "Add Leg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Dismiss Button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.send(.cancelButtonTapped)
                    } label: {
                        Text("Cancel")
                    }
                }
                
                // Global Save Button
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.saveRouteButtonTapped)
                    } label: {
                        Text("Save")
                            .bold()
                    }
                    // Prevent saving an empty route
                    .disabled(store.completedLegs.isEmpty)
                }
            }
            // TCA handles mounting the alerts generated in the reducer
            .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
        }
    }
}

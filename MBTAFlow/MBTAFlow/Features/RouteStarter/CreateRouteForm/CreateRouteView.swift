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

    @Environment(\.dismiss) private var dismiss //wat dis
    
    
    //we might want some kind of display on how many stops are previous on the top
    //with dots? numbers? "Stop 3"?
    
    //this whole form needs to be modularized so we can reuse it to edit a single stop in a route.
    //some things will be creation specific "add stop", and "save route" will be "save stop", etc.
    //do later, unimportant until we have real saving mechanism
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header:
                            HStack {
                    Text("Mode of Transit")
                    Spacer() // Pushes the button all the way to the right
                    
                    // Only show the undo button if they have already made a selection
                    if store.selectedType != nil {
                        Button {
                            // Send the reset action to the Reducer
                            store.send(.resetTypeSelection)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .textCase(nil)
                    }
                }
                ) {
                    Picker("Transit Type", selection: Binding(
                        get: { store.selectedType },
                        set: { newValue in
                            // When the user picks an option, explicitly send your action
                            if let newValue {
                                store.send(.transitTypeSelected(newValue))
                            }
                        }
                    )) {
                        // Default empty state because selectedType is optional
                        Text("Select a mode").tag(TransitType?.none)
                        // Loop through the array in your state
                        ForEach(store.typeOptions, id: \.self) { type in
                            // type.rawValue outputs the string ("MBTA Bus", "Red Line", etc.)
                            Text(type.rawValue).tag(TransitType?.some(type))
                        }
                    }.disabled(store.selectedType != nil)
                }
                //invisible to start, skipped on some
                if store.currentFormStep == .selectBranch || store.selectedBranch != nil {
                    Section(header:
                                HStack {
                        Text("Branch") //display line on bus?
                        Spacer() // Pushes the button all the way to the right
                        
                        // Only show the undo button if they have already made a selection
                        if store.selectedBranch != nil {
                            Button {
                                // Send the reset action to the Reducer
                                store.send(.resetBranchSelection)
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .textCase(nil)
                        }
                    }
                    ) {
                        Picker("Branch", selection: Binding(
                            get: { store.selectedBranch },
                            set: { newValue in
                                // When the user picks an option, explicitly send your action
                                if let newValue {
                                    store.send(.branchSelected(newValue))
                                }
                            }
                        )) {
                            Text("Select a branch").tag(String?.none)
                            // Loop through the array in y.disabled(store.selectedBranch != nil)our state
                            ForEach(store.branchOptions, id: \.self) { branch in
                                // type.rawValue outputs the string ("MBTA Bus", "Red Line", etc.)
                                Text(branch).tag(String?.some(branch))
                            }
                        }.disabled(store.selectedBranch != nil)
                    }
                    
                }
                //direction. Also skipped on some? Investigate
                if store.currentFormStep == .selectDirection || store.selectedDirection != nil {
                    Section(header:
                                HStack {
                        Text("Direction")
                        Spacer() // Pushes the button all the way to the right
                        
                        // Only show the undo button if they have already made a selection
                        if store.selectedDirection != nil {
                            Button {
                                // Send the reset action to the Reducer
                                store.send(.resetDirectionSelection)
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .textCase(nil)
                        }
                    }
                    ) {
                        Picker("Direction", selection: Binding(
                            get: { store.selectedDirection },
                            set: { newValue in
                                // When the user picks an option, explicitly send your action
                                if let newValue {
                                    store.send(.directionSelected(newValue, store.routeId ?? ""))
                                }
                            }
                        )) {
                            // Default empty state because selectedType is optional
                            Text("Select a direction").tag(String?.none)
                            // Loop through the array in your state
                            ForEach(store.directionOptions, id: \.self) { direction in
                                
                                Text(direction).tag(String?.some(direction))
                            }
                        }.disabled(store.selectedDirection != nil)
                    }
                }
                //stop itself
                if store.currentFormStep == .selectStop || store.selectedStop != nil {
                    Section(header: Text("Stop")) {
                        Picker("Stop", selection: Binding(
                            get: { store.selectedStop }, // Fixed binding
                            set: { newValue in
                                if let newValue {
                                    store.send(.stopSelected(newValue))
                                }
                            }
                        )) {
                            Text("Select a stop").tag(String?.none)
                            ForEach(store.stopOptions, id: \.self) { stop in
                                Text(stop).tag(String?.some(stop))
                            }
                        } //.disabled(store.selectedStop != nil)
                    }
                }
                
                if store.currentFormStep == .selectStop && store.selectedStop != nil {
                    Section {
                        HStack {
                            // Secondary Action: Transparent background with a tinted border/text
                            Button("Add Another Stop") {
                                store.send(.addStopButtonTapped)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            
                            Spacer()
                            Button("Save Route") {
                                store.send(.saveRouteButtonTapped)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Create Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

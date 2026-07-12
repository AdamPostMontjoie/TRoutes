//
//  RouteReviewView.swift
//  TRoutes
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import SwiftUI

struct RouteReviewView: View {
    @Bindable var store: StoreOf<RouteReviewFeature>
    
    //might want to add leave without saving confirmation here
    @FocusState private var isNameFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Route Name", text: $store.route.name)
                    .font(.headline)
                    .focused($isNameFocused)
                    .onChange(of: isNameFocused) { oldValue, newValue in
                        if newValue == false {
                            store.send(.nameEditingEnded)
                        }
                    }
                    .onSubmit {
                        isNameFocused = false
                    }
            }

            Section(header: Text("Legs")) {
                ForEach(
                    store.scope(state: \.legRows, action: \.legRows)
                ) { childStore in
                    LegRowView(store: childStore)
                }

                Button {
                    store.send(.addLegButtonTapped)
                } label: {
                    HStack {
                        Spacer()
                        Label("Add Leg", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("Review Route")
        .sheet(
            item: $store.scope(state: \.destination?.editLeg, action: \.destination.editLeg)
        ) { editLegStore in
            EditLegView(store: editLegStore)
        }
        .sheet(
            item: $store.scope(state: \.destination?.addLegs, action: \.destination.addLegs)
        ) { addLegsStore in
            AddLegsToRouteView(store: addLegsStore)
        }
    }
}

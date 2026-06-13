//
//  RouteReviewView.swift
//  MBTAFlow
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
            }
        }
        .navigationTitle("Review Route")
        .sheet(
            item: $store.scope(state: \.destination?.editLeg, action: \.destination.editLeg)
        ) { editLegStore in
            EditLegView(store: editLegStore)
        }
    }
}

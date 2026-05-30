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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    LabeledContent("Route name", value: store.routeName)
                    LabeledContent("Starting stop", value: store.startingStop)
                    LabeledContent("Ending stop", value: store.endingStop)
                    LabeledContent("Departure time", value: store.departureTime)
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

//
//  LegFormView.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/12/26.
//

import ComposableArchitecture
import SwiftUI

struct LegFormView: View {
    @Bindable var store: StoreOf<LegFormFeature>

    @Environment(\.dismiss) private var dismiss //wat dis

    //we might want some kind of display on how many stops are previous on the top
    //with dots? numbers? "Stop 3"?

    //this whole form needs to be modularized so we can reuse it to edit a single stop in a route.
    //some things will be creation specific "add stop", and "save route" will be "save stop", etc.
    //do later, unimportant until we have real saving mechanism

    var body: some View {
        NavigationStack {
            Form {
                transitTypeSection
                branchSection
                directionSection
                startStopSection
                endStopSection
                routeActionSection
            }
            .onAppear {
                store.send(.onAppear)
            }
            .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.closeButtonTapped)
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var transitTypeSection: some View {
        Section(header: resetHeader(
            title: "Mode of Transit",
            isResetVisible: store.selectedType != nil,
            action: .resetTypeSelection
        )) {
            Picker("Transit Type", selection: transitTypeSelection) {
                Text("Select a mode").tag(TransitType?.none)
                ForEach(store.typeOptions, id: \.self) { type in
                    Text(type.rawValue).tag(TransitType?.some(type))
                }
            }
            .disabled(store.selectedType != nil)
        }
    }

    @ViewBuilder
    private var branchSection: some View {
        if store.currentFormStep == .selectBranch || store.selectedBranch != nil {
            Section(header: resetHeader(
                title: "Branch",
                isResetVisible: store.selectedBranch != nil,
                action: .resetBranchSelection
            )) {
                Picker("Branch", selection: branchSelection) {
                    Text("Select a branch").tag(TransitBranch?.none)
                    ForEach(store.branchOptions ?? [], id: \.self) { branch in
                        Text(branch.displayName).tag(TransitBranch?.some(branch))
                    }
                }
                .disabled(store.selectedBranch != nil)
            }
        }
    }

    @ViewBuilder
    private var directionSection: some View {
        if store.currentFormStep == .selectDirection || store.selectedDirection != nil {
            Section(header: resetHeader(
                title: "Direction",
                isResetVisible: store.selectedDirection != nil,
                action: .resetDirectionSelection
            )) {
                Picker("Direction", selection: directionSelection) {
                    Text("Select a direction").tag(TransitDirection?.none)
                    ForEach(store.directionOptions ?? [], id: \.self) { direction in
                        Text("\(direction.directionName) - \(direction.destination)")
                            .tag(TransitDirection?.some(direction))
                    }
                }
                .disabled(store.selectedDirection != nil)
            }
        }
    }

    @ViewBuilder
    private var startStopSection: some View {
        if store.currentFormStep == .selectStartStop || store.selectedStartStop != nil {
            Section(header: resetHeader(
                title: "Origin",
                isResetVisible: store.selectedStartStop != nil,
                action: .resetStartStopSelection
            )) {
                Picker("Stop", selection: startStopSelection) {
                    Text("Select a starting stop").tag(UUID?.none)
                    ForEach(store.stopOptions.dropLast(), id: \.id) { stop in
                        Text(stop.stopName).tag(UUID?.some(stop.id))
                    }
                }
                .disabled(store.selectedStartStop != nil)
            }
        }
    }

    @ViewBuilder
    private var endStopSection: some View {
        if store.currentFormStep == .selectEndStop || store.selectedEndStop != nil {
            Section(header: Text("Destination")) {
                Picker("Stop", selection: endStopSelection) {
                    Text("Select a destination stop").tag(UUID?.none)
                    //prevents going backwards on a route
                    let validEndStops = Array(
                        store.stopOptions
                            .drop(while: { $0.mbtaStopId != store.selectedStartStop?.mbtaStopId })
                            .dropFirst()
                    )
                    ForEach(validEndStops, id: \.id) { stop in
                        Text(stop.stopName).tag(UUID?.some(stop.id))
                    }
                }
                .disabled(store.selectedEndStop != nil)
            }
        }
    }

    @ViewBuilder
    private var routeActionSection: some View {
        if store.currentFormStep == .selectEndStop && store.selectedEndStop != nil && store.currentLeg != nil {
            Section {
                if store.mode == .create {
                    HStack {
                        Button("Add Another Leg") {
                            store.send(.primaryButtonTapped)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        Spacer()
                        
                        Button(saveButtonText) {
                            store.send(.saveButtonTapped)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    Button(saveButtonText) {
                        store.send(.saveButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func resetHeader(
        title: String,
        isResetVisible: Bool,
        action: LegFormFeature.Action
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            if isResetVisible {
                Button {
                    store.send(action)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .textCase(nil)
            }
        }
    }

    private var transitTypeSelection: Binding<TransitType?> {
        Binding(
            get: { store.selectedType },
            set: { newValue in
                if let newValue {
                    store.send(.transitTypeSelected(newValue))
                }
            }
        )
    }

    private var branchSelection: Binding<TransitBranch?> {
        Binding(
            get: { store.selectedBranch },
            set: { newValue in
                if let newValue {
                    store.send(.branchSelected(newValue))
                }
            }
        )
    }

    private var directionSelection: Binding<TransitDirection?> {
        Binding(
            get: { store.selectedDirection },
            set: { newValue in
                if let newValue {
                    store.send(.directionSelected(newValue, store.mbtaRouteId ?? ""))
                }
            }
        )
    }

    private var startStopSelection: Binding<UUID?> {
        Binding(
            get: { store.selectedStartStop?.id },
            set: { newValue in
                if let newValue,
                   let stop = store.stopOptions.first(where: { $0.id == newValue }) {
                    store.send(.startStopSelected(stop))
                }
            }
        )
    }

    private var endStopSelection: Binding<UUID?> {
        Binding(
            get: { store.selectedEndStop?.id },
            set: { newValue in
                if let newValue,
                   let stop = store.stopOptions.first(where: { $0.id == newValue }) {
                    store.send(.endStopSelected(stop))
                }
            }
        )
    }
    private var saveButtonText: String {
        if store.mode == .create {
            return "Complete Route"
        } else {
            return "Save Changes"
        }
    }

    private var navigationTitle: String {
        if store.mode == .create {
            return "Add Leg to Route"
        } else {
            return "Edit Leg"
        }
    }
}


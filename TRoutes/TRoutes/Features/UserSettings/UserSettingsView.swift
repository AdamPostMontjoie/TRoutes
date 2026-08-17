//
//  UserSettingsView.swift
//  TRoutes
//
//  Created by Adam Post on 6/14/26.
//

import ComposableArchitecture
import SwiftUI

struct UserSettingsView: View {
    @Bindable var store: StoreOf<UserSettingsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Paste your API key",
                        text: $store.apiKeyInput.sending(\.apiKeyInputChanged)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit {
                        store.send(.apiKeySubmitted)
                    }
                    
                    Button {
                        store.send(.apiKeySubmitted)
                    } label: {
                        Text("Save Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.apiKeyInput.isEmpty)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                } header: {
                    Text("MBTA Developer Key")
                } footer: {
                    HStack(spacing: 4) {
                        Text("Don't have a key?")
                        Link(destination: URL(string: "https://api-v3.mbta.com/portal")!) {
                            HStack(spacing: 2) {
                                Text("Get one free")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                        }
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                }
                
                if store.isDebugAvailable {
                    Toggle(
                        "Journey Engine Debug",
                        isOn: Binding(
                            get: { store.isDebugEnabled },
                            set: { store.send(.debugEnabledChanged($0)) }
                        )
                    )
                    Toggle(
                        "Motion Events Debug",
                        isOn: Binding(
                            get: { store.isMotionEventsEnabled },
                            set: { store.send(.motionEventsEnabledChanged($0)) }
                        )
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }
}


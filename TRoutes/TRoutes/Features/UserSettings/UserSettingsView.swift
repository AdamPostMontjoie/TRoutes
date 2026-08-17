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
                    if store.hasValidApiKey {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Active")
                                .bold()
                            Spacer()
                            Button("Remove", role: .destructive) {
                                store.send(.removeKeyButtonTapped)
                            }
                        }
                    } else {
                        TextField(
                            "Paste your API key",
                            text: $store.apiKeyInput.sending(\.apiKeyInputChanged)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .disabled(store.isVerifyingKey)
                        .onSubmit {
                            store.send(.apiKeySubmitted)
                        }
                        
                        if store.keyVerificationFailed {
                            Text("Invalid API Key. Please check the key and try again.")
                                .font(.caption)
                                .foregroundColor(.red)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                        
                        Button {
                            store.send(.apiKeySubmitted)
                        } label: {
                            HStack {
                                if store.isVerifyingKey {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 4)
                                }
                                Text(store.isVerifyingKey ? "Verifying..." : "Save Key")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.apiKeyInput.isEmpty || store.isVerifyingKey)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                } header: {
                    Text("MBTA Developer Key")
                } footer: {
                    if !store.hasValidApiKey{
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


//
//  UserSettingsView.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/14/26.
//

import ComposableArchitecture
import SwiftUI

struct UserSettingsView: View {
    let store: StoreOf<UserSettingsFeature>

    var body: some View {
        NavigationStack {
            Form {
                if store.isDebugAvailable {
                    Toggle(
                        "Debug Mode",
                        isOn: Binding(
                            get: { store.isDebugEnabled },
                            set: { store.send(.debugEnabledChanged($0)) }
                        )
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }
}

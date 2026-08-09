//
//  UserSettingsView.swift
//  TRoutes
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

//
//  EditLegView.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/13/26.
//

import ComposableArchitecture
import SwiftUI

struct EditLegView: View {
    @Bindable var store: StoreOf<EditLegFeature>

    var body: some View {
        LegFormView(
            store: store.scope(
                state: \.legForm,
                action: \.legForm
            )
        )
        .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
    }
}

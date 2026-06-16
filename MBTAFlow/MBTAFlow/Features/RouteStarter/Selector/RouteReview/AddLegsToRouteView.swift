//
//  AddLegsToRouteView.swift
//  MBTAFlow
//
//  Created by Coding Assistant on 6/14/26.
//

import ComposableArchitecture
import SwiftUI

struct AddLegsToRouteView: View {
    @Bindable var store: StoreOf<AddLegsToRouteFeature>

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

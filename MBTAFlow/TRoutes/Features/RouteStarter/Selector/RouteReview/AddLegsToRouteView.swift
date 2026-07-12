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
        .disabled(store.isSaving)
        .overlay {
            if store.isSaving {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Saving...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
    }
}

//
//  CreateStepView.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct CreateRouteView: View {
    @Bindable var store: StoreOf<CreateRouteFeature>
    
    var body: some View {
        NavigationStack {
            VStack {
                // If they have completed legs, you can show a mini-timeline at the top here later
                if !store.completedLegs.isEmpty && store.legForm.currentLeg == nil {
                    Text("\(store.completedLegs.count) legs added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                
                // Inject the isolated child form
                LegFormView(
                    store: store.scope(
                        state: \.legForm,
                        action: \.legForm
                    )
                )
                .disabled(store.isSaving)
            }
            .overlay {
                if store.isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Saving route...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
        }
    }

}

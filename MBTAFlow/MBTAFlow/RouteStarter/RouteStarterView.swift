//
//  RouteStarterView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import SwiftUI
import ComposableArchitecture

struct RouteStarterView: View {
    @Bindable var store: StoreOf<RouteStarterFeature>

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SelectorView(
                    store: store.scope(
                        state: \.routeSelector,
                        action: \.routeSelector
                    )
                )
                .navigationTitle("Routes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.send(.onCreateButtonTapped)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                if store.isActiveRoutePresented {
                    ActiveRouteView(
                        store: store.scope(
                            state: \.activeRoute,
                            action: \.activeRoute
                        )
                    )
                    .padding(.top, 8)
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.isCreateRoutePresented },
                set: { isPresented in
                    if !isPresented {
                        store.send(.onCreateRouteDismissed)
                    }
                }
            )
        ) {
            CreateRouteView(
                store: store.scope(
                    state: \.createRoute,
                    action: \.createRoute
                )
            )
        }
    }
}

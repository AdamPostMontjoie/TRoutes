//
//  SelectorView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI


struct SelectorView<Header: View>: View {
    @Bindable var store: StoreOf<SelectorFeature>
    let header: Header
    
    init(store: StoreOf<SelectorFeature>, @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.store = store
        self.header = header()
    }
    
    var body: some View {
        List {
            header //supports debug dashboard
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            
            ForEach(store.userRoutes) { userRoute in
                NavigationLink(state: RouteReviewFeature.State(
                    route: makeUserRouteForEditing(from: userRoute)
                )) {
                    HStack {
                        Text(userRoute.name)

                        Spacer()

                        Button {
                            store.send(.startButtonTapped(userRoute.id))
                        } label: {
                            Text("Start")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.send(.deleteButtonTapped(userRoute.id))
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                
            }
        }
        .listStyle(.plain)
        .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
        .onAppear {
            store.send(.fetchRoutesFromDisk)
        }
    }
}

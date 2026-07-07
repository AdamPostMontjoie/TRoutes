//
//  SelectorView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI


struct SelectorView: View {
    @Bindable var store: StoreOf<SelectorFeature>
    
    //if a user side swipes on item in list, it will present delete option.
    //button to start route
    //clicking on route will bring to page displaying the route info (stops, directions, etc. with another start option)
    
    var body: some View {
        List {
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

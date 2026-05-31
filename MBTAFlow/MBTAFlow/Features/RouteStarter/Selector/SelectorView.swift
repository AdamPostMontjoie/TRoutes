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
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                ForEach(store.userRoutes) { userRoute in
                    NavigationLink(state: RouteReviewFeature.State(route: userRoute)) {
                        Text(userRoute.name)
                    }
                    
                }
            }
            .listStyle(.plain)
        } destination: { store in
            RouteReviewView(store: store)
        }
    }
}


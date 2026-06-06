//
//  RouteReviewView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import SwiftUI

struct RouteReviewView: View {
    @Bindable var store: StoreOf<RouteReviewFeature>

    var body: some View {
        //make this a header
        List {
            // Header for the Route Name
            Section {
                Text(store.route.name)
                    .font(.headline)
            }
            
            // The Stops List
            Section(header: Text("Leg stops")) {
                // Point the id directly to the unique string variable inside your Stop struct
                ForEach(
                    store.scope(state: \.stops, action: \.stops)
                ) { childStore in
                    StopRowView(store: childStore)
                }
            }
        }
        .navigationTitle("Review Route")
    }
}


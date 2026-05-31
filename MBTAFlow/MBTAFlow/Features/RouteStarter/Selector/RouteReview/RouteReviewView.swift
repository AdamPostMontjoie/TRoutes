//
//  RouteReviewView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

import ComposableArchitecture
import SwiftUI

struct RouteReviewView: View {
    let store: StoreOf<RouteReviewFeature>

    var body: some View {
        Text(store.route.name)
    }
}

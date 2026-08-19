//
//  SearchedStationFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import SwiftUI
import ComposableArchitecture

struct StopSearchView: View {
    @Bindable var store: StoreOf<StopSearchFeature>
    
    var body: some View {
        List {
            // Search is currently disabled
        }
        .listStyle(.plain)
    }
}

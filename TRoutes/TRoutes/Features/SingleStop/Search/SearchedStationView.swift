//
//  SearchedStationView.swift
//  TRoutes
//
//  Created by Adam Post on 8/19/26.
//

import SwiftUI
import ComposableArchitecture

struct SearchedStationView: View {
    @Bindable var store: StoreOf<SearchedStationFeature>
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(store.scope(state: \.banners, action: \.banner)) { bannerStore in
                    StopBannerView(store: bannerStore)
                }
            }
            .padding()
        }
        .navigationTitle(store.station.stationName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

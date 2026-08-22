//
//  StopsListView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import SwiftUI
import ComposableArchitecture

struct StopsListView: View {
    @Bindable var store: StoreOf<StopsListFeature>
    
    var body: some View {
        List {
            if !store.pinnedBanners.isEmpty {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { store.isPinnedExpanded },
                        set: { store.send(.togglePinned($0)) }
                    )
                ) {
                    ForEach(
                        store.scope(state: \.pinnedBanners, action: \.pinnedBanners)
                    ) { bannerStore in
                        StopBannerView(store: bannerStore)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                } label: {
                    Text("Pinned").font(.headline)
                }
            }
            
            if !store.savedBanners.isEmpty {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { store.isSavedExpanded },
                        set: { store.send(.toggleSaved($0)) }
                    )
                ) {
                    ForEach(
                        store.scope(state: \.savedBanners, action: \.savedBanners)
                    ) { bannerStore in
                        StopBannerView(store: bannerStore)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                } label: {
                    Text("Saved").font(.headline)
                }
            }
            
            DisclosureGroup(
                isExpanded: Binding(
                    get: { store.isNearbyExpanded },
                    set: { store.send(.toggleNearby($0)) }
                )
            ) {
                ForEach(
                    store.scope(state: \.nearbyBanners, action: \.nearbyBanners)
                ) { bannerStore in
                    StopBannerView(store: bannerStore)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            } label: {
                Text("Nearby").font(.headline)
            }
        }
        .listStyle(.plain)
        .onAppear {
            store.send(.onAppear)
        }
    }
}

//
//  StopsListView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import SwiftUI
import ComposableArchitecture

struct StopsListView: View {
    @Bindable var store: StoreOf<StopsListFeature>

    private enum ScrollAnchor: Hashable {
        case nearbyHeader
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !store.pinnedBanners.isEmpty {
                    Section {
                        if store.isPinnedExpanded {
                            ForEach(
                                store.scope(state: \.pinnedBanners, action: \.pinnedBanners)
                            ) { bannerStore in
                                StopBannerView(store: bannerStore)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            title: "Pinned",
                            systemImage: "pin.fill",
                            isExpanded: store.isPinnedExpanded
                        ) {
                            store.send(.togglePinned(!store.isPinnedExpanded))
                        }
                    }
                }

                if !store.savedBanners.isEmpty {
                    Section {
                        if store.isSavedExpanded {
                            ForEach(
                                store.scope(state: \.savedBanners, action: \.savedBanners)
                            ) { bannerStore in
                                StopBannerView(store: bannerStore)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            title: "Saved",
                            systemImage: "bookmark.fill",
                            isExpanded: store.isSavedExpanded
                        ) {
                            store.send(.toggleSaved(!store.isSavedExpanded))
                        }
                    }
                }

                Section {
                    if store.isNearbyExpanded {
                        ForEach(
                            store.scope(state: \.nearbyBanners, action: \.nearbyBanners)
                        ) { bannerStore in
                            if store.nearbyFilter.includes(bannerStore.target.transitType) {
                                StopBannerView(store: bannerStore)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                } header: {
                    nearbyHeader
                        .id(ScrollAnchor.nearbyHeader)
                }
            }

            .listStyle(.plain)
            .onChange(of: store.nearbyFilter) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo(ScrollAnchor.nearbyHeader, anchor: .top)
                }
            }
            .onAppear {
                store.send(.onAppear)
            }
            .onDisappear {
                store.send(.onDisappear)
            }
        }
    }

    private func collapsibleHeader(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .textCase(nil)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var nearbyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    store.send(.toggleNearby(!store.isNearbyExpanded))
                } label: {
                    HStack(spacing: 8) {
                        Label("Nearby", systemImage: "location.fill")
                            .font(.headline)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(store.isNearbyExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(store.isNearbyExpanded ? "Expanded" : "Collapsed")
            }

            if store.isNearbyExpanded {
                Picker(
                    "Nearby transit filter",
                    selection: Binding(
                        get: { store.nearbyFilter },
                        set: { store.send(.nearbyFilterChanged($0)) }
                    )
                ) {
                    ForEach(StopsListFeature.NearbyFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 8)
        .textCase(nil)
    }
}

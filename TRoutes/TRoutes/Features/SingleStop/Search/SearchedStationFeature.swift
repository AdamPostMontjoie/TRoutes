//
//  SearchedStationFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct SearchedStationFeature {
    @ObservableState
    struct State: Equatable {
        var station: Station
        var banners: IdentifiedArrayOf<StopBannerFeature.State> = []

        init(station: Station) {
            self.station = station
            let sortedRoutes = station.stops.sorted {
                if $0.transitType.sortOrder != $1.transitType.sortOrder {
                    return $0.transitType.sortOrder < $1.transitType.sortOrder
                }
                return $0.routeId < $1.routeId
            }
            let newBanners = sortedRoutes.map { route -> StopBannerFeature.State in
                let singleStop = SingleStop(
                    stationId: station.stationId,
                    platformId: route.platformId,
                    routeId: route.routeId,
                    stopName: station.stationName,
                    transitType: route.transitType,
                    directionDestinations: route.directionDestinations
                )
                return StopBannerFeature.State(target: .saved(singleStop))
            }
            self.banners = IdentifiedArray(uniqueElements: newBanners)
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case refreshTick
        case banner(IdentifiedActionOf<StopBannerFeature>)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case liveActivityRequested(StopLiveActivityRequest)
        }
    }

    @Dependency(\.continuousClock) var clock

    private enum CancelID { case refreshTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    while !Task.isCancelled {
                        try await clock.sleep(for: .seconds(1))
                        await send(.refreshTick)
                    }
                }
                .cancellable(id: CancelID.refreshTimer, cancelInFlight: true)

            case .onDisappear:
                return .cancel(id: CancelID.refreshTimer)

            case .refreshTick:
                let visibleIds = state.banners.filter(\.isVisible).map(\.id)
                return .run { send in
                    for id in visibleIds {
                        await send(.banner(.element(id: id, action: .fetchPredictions)))
                    }
                }

            case let .banner(.element(id: _, action: .delegate(.liveActivityRequested(request)))):
                return .send(.delegate(.liveActivityRequested(request)))

            case .banner:
                return .none

            case .delegate:
                return .none
            }
        }
        .forEach(\.banners, action: \.banner) {
            StopBannerFeature()
        }
    }
}

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
        case banner(IdentifiedActionOf<StopBannerFeature>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .banner:
                return .none
            }
        }
        .forEach(\.banners, action: \.banner) {
            StopBannerFeature()
        }
    }
}

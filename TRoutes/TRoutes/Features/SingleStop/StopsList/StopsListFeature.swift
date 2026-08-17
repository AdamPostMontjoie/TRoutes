//
//  StopsListFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import ComposableArchitecture
import Foundation

@Reducer
struct StopsListFeature {
    @ObservableState
    struct State: Equatable {
        var pinnedBanners: IdentifiedArrayOf<StopBannerFeature.State> = [
            StopBannerFeature.State(target: SingleStop(stationId: "place-north", platformId: "70026", routeId: "Orange", directionId: 1, stopName: "North Station", transitType: .orangeLine, directionDestinations: ["Forest Hills", "Oak Grove"]))
        ]
        var savedBanners: IdentifiedArrayOf<StopBannerFeature.State> = [
            StopBannerFeature.State(target: SingleStop(stationId: "place-sstat", platformId: "70068", routeId: "Red", directionId: 1, stopName: "South Station", transitType: .redLine, directionDestinations: ["Ashmont/Braintree", "Alewife"]))
        ]
        var nearbyBanners: IdentifiedArrayOf<StopBannerFeature.State> = [
            StopBannerFeature.State(target: SingleStop(stationId: "place-dwnxg", platformId: "70077", routeId: "Red", directionId: 0, stopName: "Downtown Crossing", transitType: .redLine, directionDestinations: ["Ashmont/Braintree", "Alewife"])),
            StopBannerFeature.State(target: SingleStop(stationId: "place-park", platformId: "70196", routeId: "Green-B", directionId: 1, stopName: "Park Street", transitType: .greenLine, directionDestinations: ["Boston College", "Government Center"])),
            StopBannerFeature.State(target: SingleStop(stationId: "place-govmn", platformId: "70041", routeId: "Blue", directionId: 0, stopName: "Government Center", transitType: .blueLine, directionDestinations: ["Bowdoin", "Wonderland"]))
        ]
        
        var isPinnedExpanded: Bool = true
        var isSavedExpanded: Bool = true
        var isNearbyExpanded: Bool = true
    }
    
    enum Action: Equatable {
        case togglePinned(Bool)
        case toggleSaved(Bool)
        case toggleNearby(Bool)
        case pinnedBanners(IdentifiedActionOf<StopBannerFeature>)
        case savedBanners(IdentifiedActionOf<StopBannerFeature>)
        case nearbyBanners(IdentifiedActionOf<StopBannerFeature>)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .togglePinned(expanded):
                state.isPinnedExpanded = expanded
                return .none
            case let .toggleSaved(expanded):
                state.isSavedExpanded = expanded
                return .none
            case let .toggleNearby(expanded):
                state.isNearbyExpanded = expanded
                return .none
            case .pinnedBanners, .savedBanners, .nearbyBanners:
                return .none
            }
        }
        .forEach(\.pinnedBanners, action: \.pinnedBanners) {
            StopBannerFeature()
        }
        .forEach(\.savedBanners, action: \.savedBanners) {
            StopBannerFeature()
        }
        .forEach(\.nearbyBanners, action: \.nearbyBanners) {
            StopBannerFeature()
        }
    }
}

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
        var pinnedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        var savedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        var nearbyBanners: IdentifiedArrayOf<StopBannerFeature.State> = [
            StopBannerFeature.State(target: .saved(SingleStop(stationId: "place-dwnxg", platformId: "70077", routeId: "Red", stopName: "Downtown Crossing", transitType: .redLine, directionDestinations: ["Ashmont/Braintree", "Alewife"]))),
            StopBannerFeature.State(target: .saved(SingleStop(stationId: "place-pktrm", platformId: "70196", routeId: "Green-B", stopName: "Park Street", transitType: .greenLine, directionDestinations: ["Boston College", "Government Center"]))),
            StopBannerFeature.State(target: .saved(SingleStop(stationId: "place-gover", platformId: "70041", routeId: "Blue", stopName: "Government Center", transitType: .blueLine, directionDestinations: ["Bowdoin", "Wonderland"])))
        ]
        
        var isPinnedExpanded: Bool = true
        var isSavedExpanded: Bool = true
        var isNearbyExpanded: Bool = true
    }
    
    enum Action: Equatable {
        case onAppear
        case fetchSavedAndPinned
        case savedStopsResponse(Result<[SingleStop], Never>)
        case pinnedStopsResponse(Result<[PinnedStop], Never>)
        
        case togglePinned(Bool)
        case toggleSaved(Bool)
        case toggleNearby(Bool)
        case pinnedBanners(IdentifiedActionOf<StopBannerFeature>)
        case savedBanners(IdentifiedActionOf<StopBannerFeature>)
        case nearbyBanners(IdentifiedActionOf<StopBannerFeature>)
    }
    
    @Dependency(\.databaseClient) var databaseClient
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.fetchSavedAndPinned)
                
            case .fetchSavedAndPinned:
                return .run { send in
                    do {
                        let saved = try await databaseClient.fetchSavedStops()
                        await send(.savedStopsResponse(.success(saved)))
                    } catch {
                        await send(.savedStopsResponse(.success([])))
                    }
                    
                    do {
                        let pinned = try await databaseClient.fetchPinnedStops()
                        await send(.pinnedStopsResponse(.success(pinned)))
                    } catch {
                        await send(.pinnedStopsResponse(.success([])))
                    }
                }
                
            case let .savedStopsResponse(.success(stops)):
                let newBanners = stops.map { stop -> StopBannerFeature.State in
                    var bannerState = StopBannerFeature.State(target: .saved(stop))
                    bannerState.isSaved = true
                    return bannerState
                }
                state.savedBanners = IdentifiedArray(uniqueElements: newBanners)
                return .none
                
            case let .pinnedStopsResponse(.success(stops)):
                let newBanners = stops.map { stop -> StopBannerFeature.State in
                    var bannerState = StopBannerFeature.State(target: .pinned(stop))
                    bannerState.pinnedDirections = [stop.directionId]
                    return bannerState
                }
                state.pinnedBanners = IdentifiedArray(uniqueElements: newBanners)
                return .none
                
            case let .togglePinned(expanded):
                state.isPinnedExpanded = expanded
                return .none
            case let .toggleSaved(expanded):
                state.isSavedExpanded = expanded
                return .none
            case let .toggleNearby(expanded):
                state.isNearbyExpanded = expanded
                return .none
                
            case .pinnedBanners(.element(id: _, action: .delegate(.didChangePinnedStatus))),
                 .savedBanners(.element(id: _, action: .delegate(.didChangeSaveStatus))),
                 .nearbyBanners(.element(id: _, action: .delegate(.didChangeSaveStatus))),
                 .nearbyBanners(.element(id: _, action: .delegate(.didChangePinnedStatus))):
                return .send(.fetchSavedAndPinned)
                
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

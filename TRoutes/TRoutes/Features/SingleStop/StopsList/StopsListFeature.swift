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
        var nearbyBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        
        var isPinnedExpanded: Bool = true
        var isSavedExpanded: Bool = true
        var isNearbyExpanded: Bool = true
    }
    
    enum Action: Equatable {
        case onAppear
        case fetchSavedAndPinned
        case savedStopsResponse(Result<[SingleStop], Never>)
        case pinnedStopsResponse(Result<[PinnedStop], Never>)
        
        case fetchNearby(latitude: Double, longitude: Double)
        case nearbyStopsResponse(Result<[Station], Never>)
        
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
                var updatedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
                for stop in stops {
                    if var existingBanner = state.savedBanners[id: stop.id] {
                        existingBanner.target = .saved(stop)
                        existingBanner.isSaved = true
                        updatedBanners.append(existingBanner)
                    } else {
                        var newBanner = StopBannerFeature.State(target: .saved(stop))
                        newBanner.isSaved = true
                        updatedBanners.append(newBanner)
                    }
                }
                state.savedBanners = updatedBanners
                
                for id in state.nearbyBanners.ids {
                    if let nearbyBanner = state.nearbyBanners[id: id] {
                        var updatedNearby = nearbyBanner
                        updatedNearby.isSaved = state.savedBanners.contains(where: { $0.target.stationId == nearbyBanner.target.stationId && $0.target.routeId == nearbyBanner.target.routeId })
                        state.nearbyBanners[id: id] = updatedNearby
                    }
                }
                
                return .none
                
            case let .pinnedStopsResponse(.success(stops)):
                var updatedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
                for stop in stops {
                    if var existingBanner = state.pinnedBanners[id: stop.id] {
                        existingBanner.target = .pinned(stop)
                        existingBanner.pinnedDirections = [stop.directionId]
                        updatedBanners.append(existingBanner)
                    } else {
                        var newBanner = StopBannerFeature.State(target: .pinned(stop))
                        newBanner.pinnedDirections = [stop.directionId]
                        updatedBanners.append(newBanner)
                    }
                }
                state.pinnedBanners = updatedBanners
                
                for id in state.savedBanners.ids {
                    if let savedBanner = state.savedBanners[id: id] {
                        var updatedSaved = savedBanner
                        updatedSaved.pinnedDirections.removeAll()
                        for pinnedBanner in state.pinnedBanners {
                            if pinnedBanner.target.stationId == savedBanner.target.stationId && pinnedBanner.target.routeId == savedBanner.target.routeId {
                                updatedSaved.pinnedDirections.formUnion(pinnedBanner.pinnedDirections)
                            }
                        }
                        state.savedBanners[id: id] = updatedSaved
                    }
                }
                
                for id in state.nearbyBanners.ids {
                    if let nearbyBanner = state.nearbyBanners[id: id] {
                        var updatedNearby = nearbyBanner
                        updatedNearby.pinnedDirections.removeAll()
                        for pinnedBanner in state.pinnedBanners {
                            if pinnedBanner.target.stationId == nearbyBanner.target.stationId && pinnedBanner.target.routeId == nearbyBanner.target.routeId {
                                updatedNearby.pinnedDirections.formUnion(pinnedBanner.pinnedDirections)
                            }
                        }
                        state.nearbyBanners[id: id] = updatedNearby
                    }
                }
                
                return .none
                
            case let .fetchNearby(latitude, longitude):
                return .run { send in
                    do {
                        let stations = try await databaseClient.findNearbyStations(latitude, longitude, 100)
                        await send(.nearbyStopsResponse(.success(stations)))
                    } catch {
                        await send(.nearbyStopsResponse(.success([])))
                    }
                }
                
            case let .nearbyStopsResponse(.success(stations)):
                var newBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
                for station in stations {
                    for stop in station.stops {
                        let singleStop = SingleStop(
                            stationId: station.stationId,
                            platformId: stop.platformId,
                            routeId: stop.routeId,
                            stopName: station.stationName,
                            transitType: stop.transitType,
                            directionDestinations: stop.directionDestinations
                        )
                        var banner = StopBannerFeature.State(target: .saved(singleStop))
                        
                        // Sync with existing saved state
                        if state.savedBanners.contains(where: { $0.target.stationId == singleStop.stationId && $0.target.routeId == singleStop.routeId }) {
                            banner.isSaved = true
                        }
                        // Sync with existing pinned state
                        for pinnedBanner in state.pinnedBanners {
                            if pinnedBanner.target.stationId == singleStop.stationId && pinnedBanner.target.routeId == singleStop.routeId {
                                banner.pinnedDirections.formUnion(pinnedBanner.pinnedDirections)
                            }
                        }
                        
                        newBanners.append(banner)
                    }
                }
                state.nearbyBanners = newBanners
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
                 .savedBanners(.element(id: _, action: .delegate(.didChangePinnedStatus))),
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

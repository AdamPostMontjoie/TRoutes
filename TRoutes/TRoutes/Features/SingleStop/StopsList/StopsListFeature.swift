//
//  StopsListFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
import ComposableArchitecture
import CoreLocation
import Foundation

@Reducer
struct StopsListFeature {
    enum NearbyFilter: String, CaseIterable, Equatable {
        case all
        case subway
        case bus
        case commuterRail

        var title: String {
            switch self {
            case .all: return "All"
            case .subway: return "Subway"
            case .bus: return "Bus"
            case .commuterRail: return "CR"
            }
        }

        func includes(_ transitType: TransitType) -> Bool {
            switch self {
            case .all:
                return true
            case .subway:
                switch transitType {
                case .redLine, .orangeLine, .blueLine, .greenLine, .mattapan:
                    return true
                case .bus, .commuterRail, .ferry:
                    return false
                }
            case .bus:
                if case .bus = transitType { return true }
                return false
            case .commuterRail:
                if case .commuterRail = transitType { return true }
                return false
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var pinnedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        var savedBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        var nearbyBanners: IdentifiedArrayOf<StopBannerFeature.State> = []
        var displayCoordinates: CLLocationCoordinate2D?
        var nearbyFilter: NearbyFilter = .all
        
        var isPinnedExpanded: Bool = true
        var isSavedExpanded: Bool = true
        var isNearbyExpanded: Bool = true
    }
    
    enum Action: Equatable {
        case onAppear
        case onDisappear
        case refreshTick
        case fetchSavedAndPinned
        case savedStopsResponse(Result<[SingleStop], Never>)
        case pinnedStopsResponse(Result<[PinnedStop], Never>)
        
        case fetchNearby(latitude: Double, longitude: Double)
        case nearbyStopsResponse(Result<[Station], Never>)
        case displayCoordinatesUpdated(CLLocationCoordinate2D)
        case nearbyFilterChanged(NearbyFilter)
        
        case togglePinned(Bool)
        case toggleSaved(Bool)
        case toggleNearby(Bool)
        case pinnedBanners(IdentifiedActionOf<StopBannerFeature>)
        case savedBanners(IdentifiedActionOf<StopBannerFeature>)
        case nearbyBanners(IdentifiedActionOf<StopBannerFeature>)
    }
    
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case refreshTimer }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .send(.fetchSavedAndPinned),
                    .run { send in
                        while !Task.isCancelled {
                            try await clock.sleep(for: .seconds(1))
                            await send(.refreshTick)
                        }
                    }
                    .cancellable(id: CancelID.refreshTimer, cancelInFlight: true)
                )

            case .onDisappear:
                return .cancel(id: CancelID.refreshTimer)

            case .refreshTick:
                let pinnedIds = state.pinnedBanners.filter(\.isVisible).map(\.id)
                let savedIds = state.savedBanners.filter(\.isVisible).map(\.id)
                let nearbyIds = state.nearbyBanners.filter(\.isVisible).map(\.id)
                return .run { send in
                    for id in pinnedIds {
                        await send(.pinnedBanners(.element(id: id, action: .fetchPredictions)))
                    }
                    for id in savedIds {
                        await send(.savedBanners(.element(id: id, action: .fetchPredictions)))
                    }
                    for id in nearbyIds {
                        await send(.nearbyBanners(.element(id: id, action: .fetchPredictions)))
                    }
                }
                
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
                    let target = BannerTarget.saved(stop)
                    let bannerId = StopBannerFeature.State.ID(target: target)
                    if var existingBanner = state.savedBanners[id: bannerId] {
                        existingBanner.target = .saved(stop)
                        existingBanner.isSaved = true
                        updatedBanners.append(existingBanner)
                    } else {
                        var newBanner = StopBannerFeature.State(target: target)
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
                    let target = BannerTarget.pinned(stop)
                    let bannerId = StopBannerFeature.State.ID(target: target)
                    if var existingBanner = state.pinnedBanners[id: bannerId] {
                        existingBanner.target = .pinned(stop)
                        existingBanner.pinnedDirections = [stop.directionId]
                        updatedBanners.append(existingBanner)
                    } else {
                        var newBanner = StopBannerFeature.State(target: target)
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

            case let .displayCoordinatesUpdated(coordinates):
                state.displayCoordinates = coordinates
                for id in state.nearbyBanners.ids {
                    state.nearbyBanners[id: id]?.userCoordinates = coordinates
                }
                return .none

            case let .nearbyFilterChanged(filter):
                state.nearbyFilter = filter
                return .none
                
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
                        let target = BannerTarget.saved(singleStop)
                        let bannerId = StopBannerFeature.State.ID(target: target)
                        var banner = state.nearbyBanners[id: bannerId]
                            ?? StopBannerFeature.State(target: target)
                        banner.target = target
                        banner.stopCoordinates = CLLocationCoordinate2D(
                            latitude: station.latitude,
                            longitude: station.longitude
                        )
                        banner.userCoordinates = state.displayCoordinates
                        
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

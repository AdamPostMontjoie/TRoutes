//
//  StopSearchFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct StopSearchFeature {
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var results: [Station] = []
    }

    enum Action: Equatable {
        case queryChanged(String)
        case searchResponse([Station])
        case stationTapped(Station)
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case stationTapped(Station)
        }
    }

    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case search }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .queryChanged(query):
                state.query = query
                if query.isEmpty {
                    state.results = []
                    return .cancel(id: CancelID.search)
                }
                return .run { send in
                    try await self.clock.sleep(for: .milliseconds(300))
                    do {
                        let results = try await self.databaseClient.searchStations(query)
                        await send(.searchResponse(results))
                    } catch {
                        await send(.searchResponse([]))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResponse(results):
                state.results = results
                return .none

            case let .stationTapped(station):
                return .send(.delegate(.stationTapped(station)))
                
            case .delegate:
                return .none
            }
        }
    }
}

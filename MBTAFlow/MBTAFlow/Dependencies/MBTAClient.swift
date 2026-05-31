//
//  MBTAClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

//this will fetch whatever route times we need once we either A. Start a route B. Enter step location
struct MBTAClient {
    var fetchTransitTimes: @Sendable (String) async throws -> String
    var fetchDirections: @Sendable (String) async throws -> String
    var fetchBranches: @Sendable (String) async throws -> String
    var fetchStops: @Sendable (String, String) async throws -> String
    var fetchRoutes: @Sendable (String, String) async throws -> String
}

extension MBTAClient:DependencyKey {
    static let liveValue = Self(
        fetchTransitTimes: { word in
            //predictions
            return word
        },
        fetchDirections: { word in
            return word
        },
        fetchBranches: { word in
            return word
        },
        fetchStops: { direction, routeId in
            return direction
        },
        fetchRoutes: { filterKey,filterValue in
            return "routes"
        }
    )
    static let testValue: Self = .liveValue //TODO figure out what the hell this is even about later
}

extension DependencyValues {
    var mbtaClient: MBTAClient {
        get { self[MBTAClient.self] }
        set { self[MBTAClient.self] = newValue }
    }
}

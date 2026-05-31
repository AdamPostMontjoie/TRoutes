//
//  DatabaseClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//

import ComposableArchitecture
import Foundation

struct DatabaseClient {
    var saveRoute: @Sendable (RouteStruct) async throws -> Void
    var updateRoute: @Sendable (RouteStruct) async throws -> Void
    var deleteRoute: @Sendable (UUID) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    static let liveValue = Self(
        saveRoute: { route in
            //save ts to swiftdata
        },
        updateRoute:  {newRoute in
            //take the uuid and overwrite whatever currently has it
        },
        deleteRoute: { routeId in
            //remove from swiftdata
        }
    )

    static let testValue: Self = .liveValue
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}

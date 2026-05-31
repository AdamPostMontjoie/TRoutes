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
    var editRouteName: @Sendable (String) async throws -> Void
    var deleteRoute: @Sendable (UUID) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    static let liveValue = Self(
        saveRoute: { route in
            //save ts to swiftdata
        },
        editRouteName: { newName in
            
            
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

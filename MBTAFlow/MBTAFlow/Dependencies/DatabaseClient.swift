//
//  DatabaseClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//

import ComposableArchitecture
import Foundation
import SwiftData

struct DatabaseClient {
    var saveRoute: @Sendable ([Leg]) async throws -> Void
    var updateRoute: @Sendable (RouteStruct) async throws -> Void
    var deleteRoute: @Sendable (UUID) async throws -> Void
    var fetchSavedRoutes: @Sendable () async throws -> [RouteStruct]
}

enum DatabaseError: Error, Equatable {
    case emptyRoute
}

extension DatabaseClient: DependencyKey {
    static let liveValue = Self(
        saveRoute: { legs in
            guard let firstLeg = legs.first,
                  let lastLeg = legs.last else {
                throw DatabaseError.emptyRoute
            }

            let routeId = UUID()
            let routeName = "\(firstLeg.startStop.stopName) to \(lastLeg.endStop.stopName)"
            let savedRoute = Route(
                routeId: routeId,
                name: routeName,
                legs: legs,
                timeStamp: Date()
            )

            let container = try ModelContainer(for: Route.self)
            let context = ModelContext(container)
            context.insert(savedRoute)
            try context.save()
        },
        updateRoute:  {newRoute in
            //take the uuid and overwrite whatever currently has it
        },
        deleteRoute: { routeId in
            //remove from swiftdata
        },
        fetchSavedRoutes: {
            return []
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

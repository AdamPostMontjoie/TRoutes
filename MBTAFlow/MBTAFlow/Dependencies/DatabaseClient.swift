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
    static let liveValue:Self  = {
        let sharedContainer: ModelContainer
            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                //change this to the app group folder later
                let storeURL = appSupport.appending(path: "MBTAFlow.store")
                let configuration = ModelConfiguration(url: storeURL)
                
                sharedContainer = try ModelContainer(for: Route.self, configurations: configuration)
            } catch {
                fatalError("Failed to initialize SwiftData container: \(error)")
            }
        
        return Self(
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

                
                let context = ModelContext(sharedContainer)
                context.insert(savedRoute)
                try context.save()
            },
            updateRoute: { newRoute in
                let context = ModelContext(sharedContainer)
                let routeId = newRoute.id
                let descriptor = FetchDescriptor<Route>(
                    predicate: #Predicate { route in
                        route.localRouteId == routeId
                    }
                )

                guard let savedRoute = try context.fetch(descriptor).first else {
                    return
                }

                savedRoute.name = newRoute.name
                savedRoute.legs = newRoute.legs
                savedRoute.timeStamp = newRoute.timeStamp
                try context.save()
            },
            deleteRoute: { localRouteId in
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<Route>(
                    predicate: #Predicate { route in
                        route.localRouteId == localRouteId
                    }
                )

                for savedRoute in try context.fetch(descriptor) {
                    context.delete(savedRoute)
                }

                try context.save()
            },
            fetchSavedRoutes: {
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<Route>(
                    sortBy: [SortDescriptor(\.timeStamp, order: .reverse)]
                )

                return try context.fetch(descriptor).map { savedRoute in
                    RouteStruct(
                        legs: savedRoute.legs,
                        id: savedRoute.localRouteId,
                        name: savedRoute.name,
                        timeStamp: savedRoute.timeStamp
                    )
                }
            }
        )
    }()

    static let testValue: Self = .liveValue
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}



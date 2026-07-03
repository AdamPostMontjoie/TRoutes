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
    var saveImportedStations: @Sendable ([JsonBuilderStation]) async throws -> Void
    var saveImportedPlatforms: @Sendable ([JsonBuilderPlatform]) async throws -> Void
    var saveImportedPatterns: @Sendable ([JsonBuilderPattern]) async throws -> Void
    var saveImportedSequenceEdges: @Sendable ([JsonBuilderSequenceEdge]) async throws -> Void
    var matchTripID: @Sendable (String?, Int?, String?, Int?, String?, String?) async throws -> Void
}

enum DatabaseError: Error, Equatable {
    case emptyRoute
}

enum DatabaseImportError: Error, Equatable {
    case alreadyImported
    case missingCoordinate(entityId: String)
    case missingStation(stationId: String)
    case missingPlatform(platformId: String)
    case missingPattern(patternId: String)
}

@Model
final class TransitReferenceImportMetadata {
    @Attribute(.unique) var metadataId: String
    var schemaVersion: Int
    var feedVersion: String
    var importedAt: Date

    init(
        metadataId: String,
        schemaVersion: Int,
        feedVersion: String,
        importedAt: Date
    ) {
        self.metadataId = metadataId
        self.schemaVersion = schemaVersion
        self.feedVersion = feedVersion
        self.importedAt = importedAt
    }
}

extension DatabaseClient: DependencyKey {
    static let liveValue:Self  = {
        let metadataId = "transit-reference-data"
        let schemaVersion = 1
        let feedVersion = "jsonbuilder-v1"
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
                
                sharedContainer = try ModelContainer(
                    for: Route.self,
                    TransitStation.self,
                    TransitPlatform.self,
                    TransitPattern.self,
                    TransitSequenceEdge.self,
                    TransitReferenceImportMetadata.self,
                    configurations: configuration
                )
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
            },
            saveImportedStations: { stations in
                let context = ModelContext(sharedContainer)
                let metadataDescriptor = FetchDescriptor<TransitReferenceImportMetadata>(
                    predicate: #Predicate { metadata in
                        metadata.metadataId == metadataId
                    }
                )

                if let metadata = try context.fetch(metadataDescriptor).first,
                   metadata.schemaVersion == schemaVersion,
                   metadata.feedVersion == feedVersion {
                    throw DatabaseImportError.alreadyImported
                }

                try context.fetch(FetchDescriptor<TransitSequenceEdge>()).forEach(context.delete)
                try context.fetch(FetchDescriptor<TransitPattern>()).forEach(context.delete)
                try context.fetch(FetchDescriptor<TransitPlatform>()).forEach(context.delete)
                try context.fetch(FetchDescriptor<TransitStation>()).forEach(context.delete)
                try context.fetch(FetchDescriptor<TransitReferenceImportMetadata>()).forEach(context.delete)

                for station in stations {
                    guard let latitude = station.latitude,
                          let longitude = station.longitude else {
                        throw DatabaseImportError.missingCoordinate(entityId: station.stationId)
                    }

                    context.insert(
                        TransitStation(
                            stationId: station.stationId,
                            name: station.name,
                            latitude: latitude,
                            longitude: longitude,
                            municipality: station.municipality,
                            monitoringMode: station.monitoringMode,
                            platformIds: station.platformIds
                        )
                    )
                }

                try context.save()
            },
            saveImportedPlatforms: { platforms in
                let context = ModelContext(sharedContainer)
                let stations = try context.fetch(FetchDescriptor<TransitStation>())
                let stationsById = Dictionary(uniqueKeysWithValues: stations.map { ($0.stationId, $0) })

                for platform in platforms {
                    guard let latitude = platform.latitude,
                          let longitude = platform.longitude else {
                        throw DatabaseImportError.missingCoordinate(entityId: platform.platformId)
                    }
                    guard let station = stationsById[platform.stationId] else {
                        throw DatabaseImportError.missingStation(stationId: platform.stationId)
                    }

                    context.insert(
                        TransitPlatform(
                            platformId: platform.platformId,
                            stationId: platform.stationId,
                            name: platform.name,
                            latitude: latitude,
                            longitude: longitude,
                            transitType: platform.transitType,
                            patternIds: platform.patternIds,
                            station: station
                        )
                    )
                }

                try context.save()
            },
            saveImportedPatterns: { patterns in
                let context = ModelContext(sharedContainer)

                for pattern in patterns {
                    context.insert(
                        TransitPattern(
                            patternId: pattern.patternId,
                            routeId: pattern.routeId,
                            directionId: pattern.directionId,
                            name: pattern.name,
                            typicality: pattern.typicality,
                            isCanonical: pattern.isCanonical
                        )
                    )
                }

                try context.save()
            },
            saveImportedSequenceEdges: { sequenceEdges in
                let context = ModelContext(sharedContainer)
                let patterns = try context.fetch(FetchDescriptor<TransitPattern>())
                let platforms = try context.fetch(FetchDescriptor<TransitPlatform>())
                let patternsById = Dictionary(uniqueKeysWithValues: patterns.map { ($0.patternId, $0) })
                let platformsById = Dictionary(uniqueKeysWithValues: platforms.map { ($0.platformId, $0) })

                for sequenceEdge in sequenceEdges {
                    guard let pattern = patternsById[sequenceEdge.patternId] else {
                        throw DatabaseImportError.missingPattern(patternId: sequenceEdge.patternId)
                    }
                    guard let platform = platformsById[sequenceEdge.platformId] else {
                        throw DatabaseImportError.missingPlatform(platformId: sequenceEdge.platformId)
                    }

                    context.insert(
                        TransitSequenceEdge(
                            patternId: sequenceEdge.patternId,
                            routeId: sequenceEdge.routeId,
                            directionId: sequenceEdge.directionId,
                            sequenceNumber: sequenceEdge.sequenceNumber,
                            platformId: sequenceEdge.platformId,
                            stationId: platform.stationId,
                            sortIndex: sequenceEdge.sortIndex,
                            pattern: pattern,
                            platform: platform
                        )
                    )
                }

                context.insert(
                    TransitReferenceImportMetadata(
                        metadataId: metadataId,
                        schemaVersion: schemaVersion,
                        feedVersion: feedVersion,
                        importedAt: Date()
                    )
                )

                try context.save()
            },
            matchTripID: { routeID, directionID, currentPlatformID, currentSequenceNumber, originPlatformID, destinationPlatformID in
                let context = ModelContext(sharedContainer)
                try printLegPatternMatch(
                    context: context,
                    routeID: routeID,
                    directionID: directionID,
                    currentPlatformID: currentPlatformID,
                    currentSequenceNumber: currentSequenceNumber,
                    originPlatformID: originPlatformID,
                    destinationPlatformID: destinationPlatformID
                )
            }
        )
    }()

    static let testValue: Self = .liveValue
}

private func printLegPatternMatch(
    context: ModelContext,
    routeID: String?,
    directionID: Int?,
    currentPlatformID: String?,
    currentSequenceNumber: Int?,
    originPlatformID: String?,
    destinationPlatformID: String?
) throws {
    guard let routeID,
          let directionID else {
        print(
            """

            === Transit Trip Match ===
            FAILURE: Cannot match static sequence without route/direction.
            Route:     \(routeID ?? "nil")
            Direction: \(directionID.map(String.init) ?? "nil")
            ==========================

            """
        )
        return
    }

    let fallbackRouteID = routeID
    let fallbackDirectionID = directionID
    let edgeDescriptor = FetchDescriptor<TransitSequenceEdge>(
        predicate: #Predicate { edge in
            edge.routeId == fallbackRouteID && edge.directionId == fallbackDirectionID
        },
        sortBy: [
            SortDescriptor(\.patternId),
            SortDescriptor(\.sortIndex),
            SortDescriptor(\.sequenceNumber)
        ]
    )
    let routeDirectionEdges = try context.fetch(edgeDescriptor)
    let groupedEdges = Dictionary(grouping: routeDirectionEdges, by: \.patternId)

    let scoredPatterns = groupedEdges.map { patternID, edges in
        var score = 0
        let sortedEdges = edges.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.sequenceNumber < $1.sequenceNumber
            }
            return $0.sortIndex < $1.sortIndex
        }
        let originEdge = originPlatformID.flatMap { stopID in
            sortedEdges.first { edgeMatchesStop($0, stopID: stopID) }
        }
        let destinationEdge = destinationPlatformID.flatMap { stopID in
            sortedEdges.first { edgeMatchesStop($0, stopID: stopID) }
        }
        let currentEdge = currentPlatformID.flatMap { stopID in
            sortedEdges.first { edgeMatchesStop($0, stopID: stopID) }
        }

        if originEdge != nil {
            score += 200
        }

        if destinationEdge != nil {
            score += 200
        }

        if let originEdge,
           let destinationEdge {
            if originEdge.sequenceNumber < destinationEdge.sequenceNumber {
                score += 1_000
            } else {
                score -= 1_000
            }
        }

        if currentEdge != nil {
            score += 100
        }

        if let currentSequenceNumber,
           sortedEdges.contains(where: { $0.sequenceNumber == currentSequenceNumber }) {
            score += 80
        }

        if let currentEdge,
           let currentSequenceNumber,
           currentEdge.sequenceNumber == currentSequenceNumber {
            score += 200
        }

        if let originEdge,
           let currentSequenceNumber {
            if currentSequenceNumber <= originEdge.sequenceNumber {
                score += 150
            } else {
                score -= 500
            }
        }

        return (
            patternID: patternID,
            score: score,
            originSequence: originEdge?.sequenceNumber,
            destinationSequence: destinationEdge?.sequenceNumber,
            currentSequenceOnPattern: currentEdge?.sequenceNumber
        )
    }
    .sorted {
        if $0.score == $1.score {
            return $0.patternID < $1.patternID
        }
        return $0.score > $1.score
    }

    guard let bestPattern = scoredPatterns.first,
          bestPattern.score > 0 else {
        print(
            """

            === Transit Trip Match ===
            FAILURE: No likely static pattern for this leg.
            Route:              \(routeID)
            Direction:          \(directionID)
            Origin stop:        \(originPlatformID ?? "nil")
            Destination stop:   \(destinationPlatformID ?? "nil")
            Current stop:       \(currentPlatformID ?? "nil")
            Current sequence:   \(currentSequenceNumber.map(String.init) ?? "nil")
            Candidate edges:    \(routeDirectionEdges.count)
            ==========================

            """
        )
        return
    }

    let orderingFailure: String
    if bestPattern.originSequence == nil {
        orderingFailure = "FAILURE: Origin stop was not found on selected pattern."
    } else if bestPattern.destinationSequence == nil {
        orderingFailure = "FAILURE: Destination stop was not found on selected pattern."
    } else if let originSequence = bestPattern.originSequence,
              let destinationSequence = bestPattern.destinationSequence,
              originSequence >= destinationSequence {
        orderingFailure = "FAILURE: Stop sequence is backwards for this leg. Origin seq \(originSequence), destination seq \(destinationSequence)."
    } else if let originSequence = bestPattern.originSequence,
              let currentSequenceNumber,
              currentSequenceNumber > originSequence {
        orderingFailure = "FAILURE: Vehicle current sequence \(currentSequenceNumber) is already past origin seq \(originSequence)."
    } else {
        orderingFailure = "Sequence check: OK"
    }

    try printPatternMatch(
        context: context,
        title: "Leg-based static sequence match",
        routeID: routeID,
        directionID: directionID,
        patternID: bestPattern.patternID,
        debugLines: [
            orderingFailure,
            "Fallback score:      \(bestPattern.score)",
            "Origin stop:         \(originPlatformID ?? "nil")",
            "Origin sequence:     \(bestPattern.originSequence.map(String.init) ?? "nil")",
            "Destination stop:    \(destinationPlatformID ?? "nil")",
            "Destination sequence:\(bestPattern.destinationSequence.map { " \($0)" } ?? " nil")",
            "Current stop:        \(currentPlatformID ?? "nil")",
            "Current API sequence:\(currentSequenceNumber.map { " \($0)" } ?? " nil")",
            "Current edge seq:    \(bestPattern.currentSequenceOnPattern.map(String.init) ?? "nil")",
            "Other candidates:    \(scoredPatterns.prefix(5).map { "\($0.patternID)=\($0.score)" }.joined(separator: ", "))"
        ]
    )
}

private func edgeMatchesStop(_ edge: TransitSequenceEdge, stopID: String) -> Bool {
    edge.platformId == stopID || edge.stationId == stopID
}

private func printPatternMatch(
    context: ModelContext,
    title: String,
    routeID: String,
    directionID: Int,
    patternID: String,
    debugLines: [String] = []
) throws {
    let matchedPatternID = patternID
    let patternDescriptor = FetchDescriptor<TransitPattern>(
        predicate: #Predicate { pattern in
            pattern.patternId == matchedPatternID
        }
    )

    guard let pattern = try context.fetch(patternDescriptor).first else {
        print(
            """

            === Transit Trip Match ===
            No imported pattern found for patternId: \(matchedPatternID)
            ==========================

            """
        )
        return
    }

    let edgeDescriptor = FetchDescriptor<TransitSequenceEdge>(
        predicate: #Predicate { edge in
            edge.patternId == matchedPatternID
        },
        sortBy: [
            SortDescriptor(\.sortIndex),
            SortDescriptor(\.sequenceNumber)
        ]
    )
    let edges = try context.fetch(edgeDescriptor)
    let stations = try context.fetch(FetchDescriptor<TransitStation>())
    let stationNamesById = Dictionary(uniqueKeysWithValues: stations.map { ($0.stationId, $0.name) })

    print(
        """

        === Transit Trip Match ===
        \(title)
        Route:     \(routeID)
        Direction: \(directionID)
        Pattern:   \(pattern.patternId)
        Name:      \(pattern.name)
        Edges:     \(edges.count)
        \(debugLines.joined(separator: "\n"))

        SEQ   PLATFORM        STATION
        -----------------------------------------------
        """
    )

    for edge in edges {
        let stationName = stationNamesById[edge.stationId] ?? "Unknown station (\(edge.stationId))"
        print(
            String(
                format: "%-5d %-15@ %@",
                edge.sequenceNumber,
                edge.platformId as NSString,
                stationName
            )
        )
    }

    print("==========================\n")
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}

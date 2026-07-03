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
    var updateRoute: @Sendable (UserRoute) async throws -> Void
    var deleteRoute: @Sendable (UUID) async throws -> Void
    var fetchSavedRoutes: @Sendable () async throws -> [UserRoute]
    var saveImportedStations: @Sendable ([JsonBuilderStation]) async throws -> Void
    var saveImportedPlatforms: @Sendable ([JsonBuilderPlatform]) async throws -> Void
    var saveImportedPatterns: @Sendable ([JsonBuilderPattern]) async throws -> Void
    var saveImportedSequenceEdges: @Sendable ([JsonBuilderSequenceEdge]) async throws -> Void
    var resolveUserRoute: @Sendable (UserRoute) async throws -> ResolvedUserRoute
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
        let schemaVersion = 2
        let feedVersion = "jsonbuilder-v2"
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
                    UserRoute(
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
                            isCanonical: pattern.isCanonical,
                            stopCount: pattern.stopCount,
                            isDefaultCandidate: pattern.isDefaultCandidate,
                            defaultReason: pattern.defaultReason,
                            defaultRank: pattern.defaultRank,
                            isBranched: pattern.isBranched
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
            resolveUserRoute: { userRoute in
                let context = ModelContext(sharedContainer)
                return try resolveUserRouteStruct(userRoute, context: context)
            }
        )
    }()

    static let testValue: Self = .liveValue
}


private func resolveUserRouteStruct(
    _ userRoute: UserRoute,
    context: ModelContext
) throws -> ResolvedUserRoute {
    let resolvedLegs = try userRoute.legs.enumerated().map { legIndex, leg in
        let nextLeg = userRoute.legs.indices.contains(legIndex + 1) ? userRoute.legs[legIndex + 1] : nil
        return try resolveLeg(
            leg,
            legIndex: legIndex,
            isLastLeg: legIndex == userRoute.legs.count - 1,
            nextLeg: nextLeg,
            context: context
        )
    }

    return ResolvedUserRoute(
        legs: resolvedLegs,
        id: userRoute.id,
        name: userRoute.name,
        timeStamp: userRoute.timeStamp
    )
}

private func resolveLeg(
    _ leg: Leg,
    legIndex: Int,
    isLastLeg: Bool,
    nextLeg: Leg?,
    context: ModelContext
) throws -> ResolvedLeg {
    let directionId = try resolvedDirectionId(for: leg)
    let routeId = leg.mbtaRouteId

    let edgeDescriptor = FetchDescriptor<TransitSequenceEdge>(
        predicate: #Predicate { edge in
            edge.routeId == routeId && edge.directionId == directionId
        },
        sortBy: [
            SortDescriptor(\.patternId),
            SortDescriptor(\.sortIndex),
            SortDescriptor(\.sequenceNumber)
        ]
    )
    let routeDirectionEdges = try context.fetch(edgeDescriptor)

    guard !routeDirectionEdges.isEmpty else {
        throw ResolvedRouteError.noSequenceEdges(
            legId: leg.id,
            routeId: routeId,
            directionId: directionId
        )
    }

    let patternDescriptor = FetchDescriptor<TransitPattern>(
        predicate: #Predicate { pattern in
            pattern.routeId == routeId && pattern.directionId == directionId
        }
    )
    let patternsById = Dictionary(
        uniqueKeysWithValues: try context.fetch(patternDescriptor).map { ($0.patternId, $0) }
    )
    let platformsById = Dictionary(
        uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransitPlatform>()).map { ($0.platformId, $0) }
    )
    let stationsById = Dictionary(
        uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransitStation>()).map { ($0.stationId, $0) }
    )

    let validCandidates = Dictionary(grouping: routeDirectionEdges, by: \.patternId)
        .compactMap { patternId, edges -> PatternResolutionCandidate? in
            let sortedEdges = sortEdges(edges)
            guard let originMatch = findStopMatch(in: sortedEdges, stopId: leg.startStop.mbtaStopId),
                  let destinationMatch = findStopMatch(in: sortedEdges, stopId: leg.endStop.mbtaStopId),
                  originMatch.edgePosition < destinationMatch.edgePosition else {
                return nil
            }

            let slice = Array(sortedEdges[originMatch.edgePosition...destinationMatch.edgePosition])
            return PatternResolutionCandidate(
                patternId: patternId,
                pattern: patternsById[patternId],
                edges: slice,
                originMatch: originMatch,
                destinationMatch: destinationMatch
            )
        }

    guard !validCandidates.isEmpty else {
        throw ResolvedRouteError.noValidPattern(
            legId: leg.id,
            originStopId: leg.startStop.mbtaStopId,
            destinationStopId: leg.endStop.mbtaStopId
        )
    }

    let selectedCandidate = try selectCandidate(validCandidates, leg: leg)
    let stops = try selectedCandidate.edges.enumerated().map { stopIndex, edge in
        try makeResolvedStop(
            edge: edge,
            leg: leg,
            legIndex: legIndex,
            stopIndex: stopIndex,
            isLastStopOnLeg: stopIndex == selectedCandidate.edges.count - 1,
            isLastLeg: isLastLeg,
            nextLeg: nextLeg,
            platform: platformsById[edge.platformId],
            station: stationsById[edge.stationId],
            directionId: directionId
        )
    }

    guard let startStop = stops.first,
          let endStop = stops.last else {
        throw ResolvedRouteError.noValidPattern(
            legId: leg.id,
            originStopId: leg.startStop.mbtaStopId,
            destinationStopId: leg.endStop.mbtaStopId
        )
    }

    return ResolvedLeg(
        sourceLegId: leg.id,
        legIndex: legIndex,
        startStop: startStop,
        endStop: endStop,
        mbtaRouteId: leg.mbtaRouteId,
        mbtaDirectionId: directionId,
        transitType: leg.transitType,
        selectedPatternId: selectedCandidate.patternId,
        transitBranch: leg.transitBranch,
        transitDirection: leg.transitDirection,
        stops: stops
    )
}

private struct PatternResolutionCandidate {
    let patternId: String
    let pattern: TransitPattern?
    let edges: [TransitSequenceEdge]
    let originMatch: StopMatch
    let destinationMatch: StopMatch

    var exactEndpointMatchCount: Int {
        [originMatch, destinationMatch].filter(\.isExactPlatformMatch).count
    }

    var usesCanonicalPattern: Bool {
        pattern?.isCanonical == true
    }

    var usesDefaultPattern: Bool {
        pattern?.isDefaultCandidate == true
    }

    var defaultRank: Int {
        pattern?.defaultRank ?? Int.max
    }

    var sliceLength: Int {
        edges.count
    }
}

private struct StopMatch {
    let edgePosition: Int
    let isExactPlatformMatch: Bool
}

private func resolvedDirectionId(for leg: Leg) throws -> Int {
    if let directionId = leg.transitDirection?.directionId {
        return directionId
    }

    let startDirection = leg.startStop.mbtaDirectionId
    let endDirection = leg.endStop.mbtaDirectionId
    if startDirection == endDirection {
        return startDirection
    }

    throw ResolvedRouteError.missingDirection(legId: leg.id)
}

private func sortEdges(_ edges: [TransitSequenceEdge]) -> [TransitSequenceEdge] {
    edges.sorted {
        if $0.sortIndex == $1.sortIndex {
            return $0.sequenceNumber < $1.sequenceNumber
        }
        return $0.sortIndex < $1.sortIndex
    }
}

private func findStopMatch(in edges: [TransitSequenceEdge], stopId: String) -> StopMatch? {
    if let platformIndex = edges.firstIndex(where: { $0.platformId == stopId }) {
        return StopMatch(edgePosition: platformIndex, isExactPlatformMatch: true)
    }

    if let stationIndex = edges.firstIndex(where: { $0.stationId == stopId }) {
        return StopMatch(edgePosition: stationIndex, isExactPlatformMatch: false)
    }

    return nil
}

private func selectCandidate(
    _ candidates: [PatternResolutionCandidate],
    leg: Leg
) throws -> PatternResolutionCandidate {
    let sortedCandidates = candidates.sorted { lhs, rhs in
        candidateSortKey(lhs, leg: leg) < candidateSortKey(rhs, leg: leg)
    }

    guard let bestCandidate = sortedCandidates.first else {
        throw ResolvedRouteError.noValidPattern(
            legId: leg.id,
            originStopId: leg.startStop.mbtaStopId,
            destinationStopId: leg.endStop.mbtaStopId
        )
    }

    if sortedCandidates.count > 1,
       candidateRankingKey(bestCandidate, leg: leg) == candidateRankingKey(sortedCandidates[1], leg: leg) {
        let tiedPatternIds = sortedCandidates
            .filter { candidateRankingKey($0, leg: leg) == candidateRankingKey(bestCandidate, leg: leg) }
            .map(\.patternId)
            .sorted()

        throw ResolvedRouteError.ambiguousPattern(
            legId: leg.id,
            patternIds: tiedPatternIds
        )
    }

    return bestCandidate
}

private func candidateRankingKey(
    _ candidate: PatternResolutionCandidate,
    leg: Leg
) -> PatternRankingKey {
    PatternRankingKey(
        inverseExactEndpointMatchCount: -candidate.exactEndpointMatchCount,
        branchHintMiss: branchHintMatches(candidate, leg: leg) ? 0 : 1,
        canonicalMiss: candidate.usesCanonicalPattern ? 0 : 1,
        defaultMiss: candidate.usesDefaultPattern ? 0 : 1,
        defaultRank: candidate.defaultRank,
        sliceLength: candidate.sliceLength
    )
}

private func candidateSortKey(
    _ candidate: PatternResolutionCandidate,
    leg: Leg
) -> PatternSortKey {
    PatternSortKey(
        rankingKey: candidateRankingKey(candidate, leg: leg),
        patternId: candidate.patternId
    )
}

private struct PatternRankingKey: Comparable, Equatable {
    let inverseExactEndpointMatchCount: Int
    let branchHintMiss: Int
    let canonicalMiss: Int
    let defaultMiss: Int
    let defaultRank: Int
    let sliceLength: Int

    static func < (lhs: PatternRankingKey, rhs: PatternRankingKey) -> Bool {
        if lhs.inverseExactEndpointMatchCount != rhs.inverseExactEndpointMatchCount {
            return lhs.inverseExactEndpointMatchCount < rhs.inverseExactEndpointMatchCount
        }
        if lhs.branchHintMiss != rhs.branchHintMiss {
            return lhs.branchHintMiss < rhs.branchHintMiss
        }
        if lhs.canonicalMiss != rhs.canonicalMiss {
            return lhs.canonicalMiss < rhs.canonicalMiss
        }
        if lhs.defaultMiss != rhs.defaultMiss {
            return lhs.defaultMiss < rhs.defaultMiss
        }
        if lhs.defaultRank != rhs.defaultRank {
            return lhs.defaultRank < rhs.defaultRank
        }
        if lhs.sliceLength != rhs.sliceLength {
            return lhs.sliceLength < rhs.sliceLength
        }
        return false
    }
}

private struct PatternSortKey: Comparable, Equatable {
    let rankingKey: PatternRankingKey
    let patternId: String

    static func < (lhs: PatternSortKey, rhs: PatternSortKey) -> Bool {
        if lhs.rankingKey != rhs.rankingKey {
            return lhs.rankingKey < rhs.rankingKey
        }
        return lhs.patternId < rhs.patternId
    }
}

private func branchHintMatches(_ candidate: PatternResolutionCandidate, leg: Leg) -> Bool {
    guard let branchId = leg.transitBranch?.id else {
        return true
    }

    return candidate.patternId.contains(branchId) || candidate.pattern?.routeId == branchId
}

private func makeResolvedStop(
    edge: TransitSequenceEdge,
    leg: Leg,
    legIndex: Int,
    stopIndex: Int,
    isLastStopOnLeg: Bool,
    isLastLeg: Bool,
    nextLeg: Leg?,
    platform: TransitPlatform?,
    station: TransitStation?,
    directionId: Int
) throws -> ResolvedStop {
    guard let platform else {
        throw ResolvedRouteError.missingPlatform(platformId: edge.platformId)
    }
    guard let station else {
        throw ResolvedRouteError.missingStation(stationId: edge.stationId)
    }

    let overlapsWithNext = isLastStopOnLeg && nextLeg.map {
        resolvedStopMatchesUserStop(
            platformId: edge.platformId,
            stationId: station.stationId,
            userStopId: $0.startStop.mbtaStopId
        )
    } == true
    let journeyRole: JourneyStopRole
    if isLastStopOnLeg && isLastLeg {
        journeyRole = .final
    } else if isLastStopOnLeg {
        journeyRole = .transfer(overlapsNext: overlapsWithNext)
    } else {
        journeyRole = .boarding
    }

    return ResolvedStop(
        sourceLegId: leg.id,
        legIndex: legIndex,
        legStopIndex: stopIndex,
        platformId: edge.platformId,
        stationId: edge.stationId,
        mbtaStopId: edge.platformId,
        mbtaRouteId: leg.mbtaRouteId,
        mbtaDirectionId: directionId,
        stopName: station.name,
        longitude: station.longitude,
        latitude: station.latitude,
        address: station.municipality ?? leg.startStop.address,
        journeyRole: journeyRole,
        monitoringMode: station.monitoringMode.resolvedMonitoringMode,
        overlapsWithNext: overlapsWithNext
    )
}

private func resolvedStopMatchesUserStop(
    platformId: String,
    stationId: String,
    userStopId: String
) -> Bool {
    platformId == userStopId || stationId == userStopId
}

private extension String {
    var resolvedMonitoringMode: MonitoringMode {
        switch lowercased() {
        case "underground":
            return .underground
        default:
            return .surface
        }
    }
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}

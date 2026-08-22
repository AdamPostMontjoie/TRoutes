//
//  DatabaseClient.swift
//  TRoutes
//
//  Created by Adam Post on 5/30/26.
//

import ComposableArchitecture
import Foundation
import SwiftData
import CoreLocation

struct DatabaseClient {
    // Journey Engine
    var saveRoute: @Sendable ([Leg]) async throws -> Void
    var updateRoute: @Sendable (UserRoute) async throws -> Void
    var deleteRoute: @Sendable (UUID) async throws -> Void
    var fetchSavedRoutes: @Sendable () async throws -> [ResolvedUserRoute]
    var resolveUserRoute: @Sendable (UserRoute) async throws -> ResolvedUserRoute
    
    // Reference Data Import
    var saveImportedStations: @Sendable ([JsonBuilderStation]) async throws -> Void
    var saveImportedPlatforms: @Sendable ([JsonBuilderPlatform]) async throws -> Void
    var saveImportedPatterns: @Sendable ([JsonBuilderPattern]) async throws -> Void
    var saveImportedSequenceEdges: @Sendable ([JsonBuilderSequenceEdge]) async throws -> Void
    
    // Single Stop Search
    var searchStations: @Sendable (String) async throws -> [Station]
    var fetchStationDetail: @Sendable (String) async throws -> Station
    var findNearbyStations: @Sendable (Double, Double, Int) async throws -> [Station]
    
    // Single Stop Saved & Pinned
    var fetchSavedStops: @Sendable () async throws -> [SingleStop]
    var fetchPinnedStops: @Sendable () async throws -> [PinnedStop]
    var addSavedStop: @Sendable (SingleStop) async throws -> Void
    var removeSavedStop: @Sendable (SingleStop) async throws -> Void
    var addPinnedStop: @Sendable (PinnedStop) async throws -> Void
    var removePinnedStop: @Sendable (PinnedStop) async throws -> Void
}

extension DatabaseClient {
    //When this changes, it triggers importing
    public static let currentSchemaVersion = 4
    public static let currentFeedVersion = "jsonbuilder-v4"
}

enum DatabaseError: Error, Equatable {
    case emptyRoute
    case savedLimitReached
    case pinnedLimitReached
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
        let schemaVersion = DatabaseClient.currentSchemaVersion
        let feedVersion = DatabaseClient.currentFeedVersion
        let sharedContainer: ModelContainer
            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                //change this to the app group folder later
                let storeURL = appSupport.appending(path: "TRoutes.store")
                let configuration = ModelConfiguration(url: storeURL)
                
                sharedContainer = try ModelContainer(
                    for: Route.self,
                    TransitStation.self,
                    TransitPlatform.self,
                    TransitPattern.self,
                    TransitSequenceEdge.self,
                    TransitReferenceImportMetadata.self,
                    UserSavedStop.self,
                    UserPinnedStop.self,
                    configurations: configuration
                )
            } catch {
                fatalError("Failed to initialize SwiftData container: \(error)")
            }
        
        return Self(
            // MARK: - Journey Engine
            saveRoute: { legs in
                guard let firstLeg = legs.first,
                      let lastLeg = legs.last else {
                    throw DatabaseError.emptyRoute
                }

                let routeId = UUID()
                let routeName = "\(firstLeg.startStop.stopName) to \(lastLeg.endStop.stopName)"
                let timeStamp = Date()
                let context = ModelContext(sharedContainer)
                let userRoute = UserRoute(
                    legs: legs,
                    id: routeId,
                    name: routeName,
                    timeStamp: timeStamp
                )
                let resolvedRoute = try resolveUserRouteStruct(userRoute, context: context)
                let savedRoute = Route(
                    routeId: routeId,
                    name: routeName,
                    legs: resolvedRoute.legs,
                    timeStamp: timeStamp
                )
    
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

                let resolvedRoute = try resolveUserRouteStruct(newRoute, context: context)
                savedRoute.name = newRoute.name
                savedRoute.legs = resolvedRoute.legs
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
                    ResolvedUserRoute(
                        legs: savedRoute.legs,
                        id: savedRoute.localRouteId,
                        name: savedRoute.name,
                        timeStamp: savedRoute.timeStamp
                    )
                }
            },
            resolveUserRoute: { userRoute in
                let context = ModelContext(sharedContainer)
                return try resolveUserRouteStruct(userRoute, context: context)
            },
            
            // MARK: - Reference Data Import
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
                            monitoringMode: platform.monitoringMode,
                            transitType: platform.transitType.rawValue,
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

            
            // MARK: - Single Stop Search
            searchStations: { query in
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<TransitStation>(
                    predicate: #Predicate { $0.name.localizedStandardContains(query) },
                    sortBy: [SortDescriptor(\.name)]
                )
                let stations = try context.fetch(descriptor)
                
                let mappedStations = stations.map { station in
                    let stationRoutes = resolveStationRoutes(for: station)
                    return Station(
                        stationId: station.stationId,
                        stationName: station.name,
                        latitude: station.latitude,
                        longitude: station.longitude,
                        stops: stationRoutes
                    )
                }
                
                return mappedStations.sorted {
                    if $0.stops.count != $1.stops.count {
                        return $0.stops.count > $1.stops.count
                    }
                    return $0.stationName < $1.stationName
                }
            },
            fetchStationDetail: { stationId in
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<TransitStation>(
                    predicate: #Predicate { $0.stationId == stationId }
                )
                guard let station = try context.fetch(descriptor).first else {
                    throw DatabaseError.emptyRoute // or some missing station error
                }
                let stationRoutes = resolveStationRoutes(for: station)
                return Station(
                    stationId: station.stationId,
                    stationName: station.name,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    stops: stationRoutes
                )
            },
            findNearbyStations: { latitude, longitude, limit in
                let context = ModelContext(sharedContainer)
                // Start with approx 800m radius (~0.008 degrees)
                var latDelta = 0.008
                var lonDelta = 0.008
                
                var results: [Station] = []
                var totalStops = 0
                
                // Expand until we find enough stops (equilibrium), up to ~50km
                while totalStops < limit && latDelta <= 0.5 {
                    let minLat = latitude - latDelta
                    let maxLat = latitude + latDelta
                    let minLon = longitude - lonDelta
                    let maxLon = longitude + lonDelta
                    
                    let descriptor = FetchDescriptor<TransitStation>(
                        predicate: #Predicate {
                            $0.latitude >= minLat && $0.latitude <= maxLat &&
                            $0.longitude >= minLon && $0.longitude <= maxLon
                        }
                    )
                    
                    let dbStations = try context.fetch(descriptor)
                    
                    if !dbStations.isEmpty {
                        // Sort by distance using CLLocation for accuracy
                        let userLocation = CLLocation(latitude: latitude, longitude: longitude)
                        let sortedDbStations = dbStations.sorted { s1, s2 in
                            let loc1 = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                            let loc2 = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                            return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
                        }
                        
                        // Reset our counters for this expanded radius
                        results = []
                        totalStops = 0
                        
                        for station in sortedDbStations {
                            let stationRoutes = resolveStationRoutes(for: station)
                            
                            // If a station has no stops, skip it
                            guard !stationRoutes.isEmpty else { continue }
                            
                            let resolvedStation = Station(
                                stationId: station.stationId,
                                stationName: station.name,
                                latitude: station.latitude,
                                longitude: station.longitude,
                                stops: stationRoutes
                            )
                            
                            results.append(resolvedStation)
                            totalStops += stationRoutes.count
                            
                            // Enforce equilibrium: stop adding stations if we've reached our stop count limit
                            if totalStops >= limit {
                                break
                            }
                        }
                    }
                    
                    if totalStops < limit {
                        latDelta *= 2
                        lonDelta *= 2
                    }
                }
                
                return results
            },
            // MARK: - Single Stop Saved & Pinned
            fetchSavedStops: {
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<UserSavedStop>(
                    sortBy: [SortDescriptor(\.addedAt)]
                )
                return try context.fetch(descriptor).map { $0.toSingleStop() }
            },
            fetchPinnedStops: {
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<UserPinnedStop>(
                    sortBy: [SortDescriptor(\.addedAt)]
                )
                return try context.fetch(descriptor).map { $0.toPinnedStop() }
            },
            addSavedStop: { stop in
                print("addSavedStop called for \(stop.stopName) - \(stop.routeId)")
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<UserSavedStop>()
                let count = try context.fetchCount(descriptor)
                if count >= 20 { throw DatabaseError.savedLimitReached }
                
                let userStop = UserSavedStop(from: stop)
                context.insert(userStop)
                try context.save()
            },
            removeSavedStop: { stop in
                print("removeSavedStop called for \(stop.stopName) - \(stop.routeId)")
                let context = ModelContext(sharedContainer)
                let stationId = stop.stationId
                let routeId = stop.routeId
                let descriptor = FetchDescriptor<UserSavedStop>(
                    predicate: #Predicate { $0.stationId == stationId && $0.routeId == routeId }
                )
                if let saved = try context.fetch(descriptor).first {
                    context.delete(saved)
                    try context.save()
                }
            },
            addPinnedStop: { stop in
                print("addPinnedStop called for \(stop.stopName) - \(stop.routeId) dir \(stop.directionId)")
                let context = ModelContext(sharedContainer)
                let descriptor = FetchDescriptor<UserPinnedStop>()
                let count = try context.fetchCount(descriptor)
                if count >= 3 { throw DatabaseError.pinnedLimitReached }
                
                let userStop = UserPinnedStop(from: stop)
                context.insert(userStop)
                try context.save()
            },
            removePinnedStop: { stop in
                print("removePinnedStop called for \(stop.stopName) - \(stop.routeId) dir \(stop.directionId)")
                let context = ModelContext(sharedContainer)
                let stationId = stop.stationId
                let routeId = stop.routeId
                let directionId = stop.directionId
                let descriptor = FetchDescriptor<UserPinnedStop>(
                    predicate: #Predicate { $0.stationId == stationId && $0.routeId == routeId && $0.pinnedDirectionId == directionId }
                )
                if let saved = try context.fetch(descriptor).first {
                    context.delete(saved)
                    try context.save()
                }
            }
        )
    }()
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

    // Determine which route IDs to search:
    // 1. If user explicitly selected routes (multi-branch), use those
    // 2. If it's a single-route type (CR/Bus), use the selected route
    // 3. Otherwise fall back to all routes for the transit type
    let routeIds: [String]
    if let selectedIds = leg.selectedRouteIds, !selectedIds.isEmpty {
        routeIds = selectedIds
    } else if leg.transitType == .greenLine {
        routeIds = leg.transitType.routeIds
    } else if leg.transitType.requiresRouteSelection {
        routeIds = [leg.mbtaRouteId]
    } else {
        routeIds = leg.transitType.routeIds
    }

    // Fetch edges for all relevant routes in this direction (targeted, not all edges)
    var routeDirectionEdges: [TransitSequenceEdge] = []
    for routeId in routeIds {
        let desc = FetchDescriptor<TransitSequenceEdge>(
            predicate: #Predicate { edge in
                edge.routeId == routeId && edge.directionId == directionId
            },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.sequenceNumber)]
        )
        routeDirectionEdges.append(contentsOf: try context.fetch(desc))
    }

    guard !routeDirectionEdges.isEmpty else {
        throw ResolvedRouteError.noSequenceEdges(
            legId: leg.id,
            routeId: routeIds.first ?? leg.mbtaRouteId,
            directionId: directionId
        )
    }

    // Fetch patterns for these routes + direction
    let patternDescriptor = FetchDescriptor<TransitPattern>(
        predicate: #Predicate { pattern in
            pattern.directionId == directionId
        }
    )
    let patternsById = Dictionary(
        uniqueKeysWithValues: try context.fetch(patternDescriptor)
            .filter { routeIds.contains($0.routeId) }
            .map { ($0.patternId, $0) }
    )

    // Fetch only the platforms and stations we actually need
    let neededPlatformIds = Set(routeDirectionEdges.map(\.platformId))
    let neededStationIds = Set(routeDirectionEdges.map(\.stationId))

    let allPlatforms = try context.fetch(FetchDescriptor<TransitPlatform>())
    let platformsById = Dictionary(
        uniqueKeysWithValues: allPlatforms
            .filter { neededPlatformIds.contains($0.platformId) }
            .map { ($0.platformId, $0) }
    )
    let allStations = try context.fetch(FetchDescriptor<TransitStation>())
    let stationsById = Dictionary(
        uniqueKeysWithValues: allStations
            .filter { neededStationIds.contains($0.stationId) }
            .map { ($0.stationId, $0) }
    )
    
    let originPlatform = allPlatforms.first(where: { $0.platformId == leg.startStop.mbtaStopId })
    let originStationId = originPlatform?.stationId
    
    let destPlatform = allPlatforms.first(where: { $0.platformId == leg.endStop.mbtaStopId })
    let destStationId = destPlatform?.stationId

    let validCandidates = Dictionary(grouping: routeDirectionEdges, by: \.patternId)
        .compactMap { patternId, edges -> PatternResolutionCandidate? in
            let sortedEdges = sortEdges(edges)
            guard let originMatch = findStopMatch(in: sortedEdges, stopId: leg.startStop.mbtaStopId, stationId: originStationId),
                  let destinationMatch = findStopMatch(in: sortedEdges, stopId: leg.endStop.mbtaStopId, stationId: destStationId),
                  originMatch.edgePosition < destinationMatch.edgePosition else {
                return nil
            }

            let slice = Array(sortedEdges[originMatch.edgePosition...destinationMatch.edgePosition])
            return PatternResolutionCandidate(
                patternId: patternId,
                pattern: patternsById[patternId],
                patternEdges: sortedEdges,
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
    let allAcceptablePatternIds = validCandidates.map(\.patternId).sorted()
    let allAcceptableRouteIds = Array(Set(validCandidates.compactMap { $0.pattern?.routeId })).sorted()
    
    let targetTransitType = selectedCandidate.edges.first?.platform?.transitType ?? originPlatform?.transitType
    
    // Group ALL platforms in the system by their parent station ID, filtering by the leg's transit type.
    // This allows acceptableStopIds to contain every platform at a station for THIS transit type, 
    // ensuring we don't miss an arrival if a vehicle pulls into a sibling platform
    // or an unexpected branch platform, while excluding unrelated platforms like busways.
    let siblingPlatformsByStation = Dictionary(
        grouping: allPlatforms.filter { (targetTransitType == nil || $0.transitType == targetTransitType) && !$0.stationId.isEmpty }, 
        by: \.stationId
    )
        .mapValues { platforms in Array(Set(platforms.map(\.platformId))) }

    let patternStops = try selectedCandidate.patternEdges.enumerated().map { patternStopIndex, edge in
        try makeResolvedPatternStop(
            edge: edge,
            patternStopIndex: patternStopIndex,
            platform: platformsById[edge.platformId],
            station: stationsById[edge.stationId]
        )
    }

    let stops = try selectedCandidate.edges.enumerated().map { stopIndex, edge in
        var acceptable = siblingPlatformsByStation[edge.stationId] ?? [edge.platformId]
        if let idx = acceptable.firstIndex(of: edge.platformId) {
            acceptable.swapAt(0, idx)
        } else {
            acceptable.insert(edge.platformId, at: 0)
        }
        
        return try makeResolvedStop(
            edge: edge,
            leg: leg,
            legIndex: legIndex,
            stopIndex: stopIndex,
            patternStopIndex: selectedCandidate.originMatch.edgePosition + stopIndex,
            isLastStopOnLeg: stopIndex == selectedCandidate.edges.count - 1,
            isLastLeg: isLastLeg,
            nextLeg: nextLeg,
            platform: platformsById[edge.platformId],
            station: stationsById[edge.stationId],
            directionId: directionId,
            acceptableStopIds: acceptable
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
        acceptablePatternIds: allAcceptablePatternIds,
        acceptableRouteIds: allAcceptableRouteIds,
        transitBranch: leg.transitBranch,
        transitDirection: leg.transitDirection,
        stops: stops,
        patternStops: patternStops
    )
}

private struct PatternResolutionCandidate {
    let patternId: String
    let pattern: TransitPattern?
    let patternEdges: [TransitSequenceEdge]
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

private func findStopMatch(in edges: [TransitSequenceEdge], stopId: String, stationId: String?) -> StopMatch? {
    if let platformIndex = edges.firstIndex(where: { $0.platformId == stopId }) {
        return StopMatch(edgePosition: platformIndex, isExactPlatformMatch: true)
    }

    if let stationIndex = edges.firstIndex(where: { $0.stationId == stopId || (stationId != nil && $0.stationId == stationId) }) {
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

    // No longer throw on ties — we accept all valid patterns via acceptablePatternIds.
    // Just pick the best-ranked one for stop/pattern resolution.
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
    patternStopIndex: Int,
    isLastStopOnLeg: Bool,
    isLastLeg: Bool,
    nextLeg: Leg?,
    platform: TransitPlatform?,
    station: TransitStation?,
    directionId: Int,
    acceptableStopIds: [String]
) throws -> ResolvedStop {
    guard let platform else {
        throw ResolvedRouteError.missingPlatform(platformId: edge.platformId)
    }
    guard let station else {
        throw ResolvedRouteError.missingStation(stationId: edge.stationId)
    }

    let overlapsWithNext = true
    let journeyRole: JourneyStopRole
    if isLastStopOnLeg && isLastLeg {
        journeyRole = .final
    } else if isLastStopOnLeg {
        journeyRole = .transfer(overlapsNext: overlapsWithNext)
    } else if stopIndex == 0 {
        journeyRole = .boarding
    } else {
        journeyRole = .intermediate
    }

    return ResolvedStop(
        sourceLegId: leg.id,
        legIndex: legIndex,
        legStopIndex: stopIndex,
        patternStopIndex: patternStopIndex,
        patternEdgeSequenceNumber: edge.sequenceNumber,
        platformId: edge.platformId,
        stationId: edge.stationId,
        mbtaStopId: edge.platformId,
        mbtaRouteId: leg.mbtaRouteId,
        mbtaDirectionId: directionId,
        stopName: station.name,
        longitude: platform.longitude,
        latitude: platform.latitude,
        address: station.municipality ?? leg.startStop.address,
        acceptableStopIds: acceptableStopIds,
        journeyRole: journeyRole,
        monitoringMode: platform.monitoringMode.resolvedMonitoringMode,
        transitType: platform.transitType.resolvedGTFSTransitType,
        overlapsWithNext: overlapsWithNext
    )
}

private func makeResolvedPatternStop(
    edge: TransitSequenceEdge,
    patternStopIndex: Int,
    platform: TransitPlatform?,
    station: TransitStation?
) throws -> ResolvedPatternStop {
    guard let platform else {
        throw ResolvedRouteError.missingPlatform(platformId: edge.platformId)
    }
    guard let station else {
        throw ResolvedRouteError.missingStation(stationId: edge.stationId)
    }

    return ResolvedPatternStop(
        patternStopIndex: patternStopIndex,
        patternEdgeSequenceNumber: edge.sequenceNumber,
        platformId: edge.platformId,
        stationId: edge.stationId,
        stopName: station.name,
        monitoringMode: platform.monitoringMode.resolvedMonitoringMode,
        transitType: platform.transitType.resolvedGTFSTransitType
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
    var resolvedGTFSTransitType: GTFSTransitType {
        guard let transitType = GTFSTransitType(rawValue: self) else {
            preconditionFailure("Unknown GTFS transit type: \(self)")
        }
        return transitType
    }

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

private func resolveStationRoutes(for station: TransitStation) -> [StationStop] {
    func mapEdges(requireCanonical: Bool) -> [String: StationStop] {
        var routesDict: [String: StationStop] = [:]
        for platform in station.platforms {
            for edge in platform.sequenceEdges {
                guard let pattern = edge.pattern else { continue }
                if requireCanonical && !pattern.isCanonical { continue }
                
                let routeId = pattern.routeId
                let directionId = pattern.directionId
                let dest = pattern.name.components(separatedBy: " - ").last ?? pattern.name
                
                if routesDict[routeId] == nil {
                    routesDict[routeId] = StationStop(
                        routeId: routeId,
                        routeName: routeId,
                        transitType: transitType(for: routeId),
                        platformId: platform.platformId,
                        directionDestinations: ["", ""]
                    )
                }
                
                if directionId == 0 || directionId == 1 {
                    let existing = routesDict[routeId]?.directionDestinations[directionId] ?? ""
                    var dests = existing.isEmpty ? [] : existing.components(separatedBy: "/")
                    if !dests.contains(dest) { dests.append(dest) }
                    routesDict[routeId]?.directionDestinations[directionId] = dests.sorted().joined(separator: "/")
                }
            }
        }
        return routesDict
    }
    
    var routesDict = mapEdges(requireCanonical: true)
    // Fallback: If no canonical patterns were found, use non-canonical patterns
    // to prevent valid stops (like 84 Mass Ave) from being empty
    if routesDict.isEmpty {
        routesDict = mapEdges(requireCanonical: false)
    }
    return routesDict.values.sorted { $0.routeId < $1.routeId }
}

private func transitType(for routeId: String) -> TransitType {
    switch routeId {
    case "Red", "Mattapan": return .redLine
    case "Orange": return .orangeLine
    case "Blue": return .blueLine
    case let id where id.hasPrefix("Green-"): return .greenLine
    case let id where id.hasPrefix("CR-"): return .commuterRail
    case let id where id.hasPrefix("Boat-"): return .ferry
    default: return .bus
    }
}

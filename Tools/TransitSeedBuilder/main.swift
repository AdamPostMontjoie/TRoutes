import Foundation
import SwiftData

private let metadataId = "transit-reference-data"

@main
enum TransitSeedBuilder {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw SeedBuilderError.invalidArguments
        }

        let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let storeURL = outputDirectory.appending(path: "TransitReference.store")
        let manifestURL = outputDirectory.appending(path: "TransitSeedManifest.json")

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try removeStoreArtifacts(at: storeURL)

        let counts = try autoreleasepool {
            try buildStore(inputDirectory: inputDirectory, storeURL: storeURL)
        }
        try checkpointStore(at: storeURL)

        let manifest = TransitSeedManifest(
            schemaVersion: TransitDataVersion.schemaVersion,
            feedVersion: TransitDataVersion.feedVersion,
            storeFileName: storeURL.lastPathComponent,
            stationCount: counts.stations,
            platformCount: counts.platforms,
            patternCount: counts.patterns,
            sequenceEdgeCount: counts.sequenceEdges
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        print("Generated \(storeURL.path)")
        print(
            "Stations: \(counts.stations), platforms: \(counts.platforms), "
                + "patterns: \(counts.patterns), edges: \(counts.sequenceEdges)"
        )
    }

    @MainActor
    private static func buildStore(
        inputDirectory: URL,
        storeURL: URL
    ) throws -> SeedCounts {
        let decoder = JSONDecoder()
        let stations: [JsonBuilderStation] = try decode(
            "stations",
            from: inputDirectory,
            using: decoder
        )
        let platforms: [JsonBuilderPlatform] = try decode(
            "platforms",
            from: inputDirectory,
            using: decoder
        )
        let patterns: [JsonBuilderPattern] = try decode(
            "patterns",
            from: inputDirectory,
            using: decoder
        )
        let sequenceEdges: [JsonBuilderSequenceEdge] = try decode(
            "sequences",
            from: inputDirectory,
            using: decoder
        )

        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: TransitStation.self,
            TransitPlatform.self,
            TransitPattern.self,
            TransitSequenceEdge.self,
            TransitReferenceImportMetadata.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var stationsById: [String: TransitStation] = [:]
        for station in stations {
            guard let latitude = station.latitude,
                  let longitude = station.longitude else {
                throw SeedBuilderError.missingCoordinate(station.stationId)
            }
            let model = TransitStation(
                stationId: station.stationId,
                name: station.name,
                latitude: latitude,
                longitude: longitude,
                municipality: station.municipality,
                monitoringMode: station.monitoringMode,
                platformIds: station.platformIds
            )
            stationsById[station.stationId] = model
            context.insert(model)
        }
        try context.save()

        var platformsById: [String: TransitPlatform] = [:]
        for platform in platforms {
            guard let latitude = platform.latitude,
                  let longitude = platform.longitude else {
                throw SeedBuilderError.missingCoordinate(platform.platformId)
            }
            guard let station = stationsById[platform.stationId] else {
                throw SeedBuilderError.missingStation(platform.stationId)
            }
            let model = TransitPlatform(
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
            platformsById[platform.platformId] = model
            context.insert(model)
        }
        try context.save()

        var patternsById: [String: TransitPattern] = [:]
        for pattern in patterns {
            let model = TransitPattern(
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
            patternsById[pattern.patternId] = model
            context.insert(model)
        }
        try context.save()

        for sequenceEdge in sequenceEdges {
            guard let pattern = patternsById[sequenceEdge.patternId] else {
                throw SeedBuilderError.missingPattern(sequenceEdge.patternId)
            }
            guard let platform = platformsById[sequenceEdge.platformId] else {
                throw SeedBuilderError.missingPlatform(sequenceEdge.platformId)
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
                schemaVersion: TransitDataVersion.schemaVersion,
                feedVersion: TransitDataVersion.feedVersion,
                importedAt: Date()
            )
        )
        try context.save()

        let counts = SeedCounts(
            stations: try context.fetchCount(FetchDescriptor<TransitStation>()),
            platforms: try context.fetchCount(FetchDescriptor<TransitPlatform>()),
            patterns: try context.fetchCount(FetchDescriptor<TransitPattern>()),
            sequenceEdges: try context.fetchCount(FetchDescriptor<TransitSequenceEdge>())
        )
        guard counts.stations == stations.count,
              counts.platforms == platforms.count,
              counts.patterns == patterns.count,
              counts.sequenceEdges == sequenceEdges.count else {
            throw SeedBuilderError.countMismatch
        }
        return counts
    }

    private static func decode<Value: Decodable>(
        _ name: String,
        from directory: URL,
        using decoder: JSONDecoder
    ) throws -> [Value] {
        let url = directory.appending(path: "\(name).json")
        return try decoder.decode([Value].self, from: Data(contentsOf: url))
    }

    private static func checkpointStore(at storeURL: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            storeURL.path,
            "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;"
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            throw SeedBuilderError.checkpointFailed(String(decoding: data, as: UTF8.self))
        }

        try removeIfPresent(URL(fileURLWithPath: storeURL.path + "-wal"))
        try removeIfPresent(URL(fileURLWithPath: storeURL.path + "-shm"))
    }

    private static func removeStoreArtifacts(at storeURL: URL) throws {
        try removeIfPresent(storeURL)
        try removeIfPresent(URL(fileURLWithPath: storeURL.path + "-wal"))
        try removeIfPresent(URL(fileURLWithPath: storeURL.path + "-shm"))
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private struct SeedCounts {
    let stations: Int
    let platforms: Int
    let patterns: Int
    let sequenceEdges: Int
}

private enum SeedBuilderError: LocalizedError {
    case invalidArguments
    case missingCoordinate(String)
    case missingStation(String)
    case missingPlatform(String)
    case missingPattern(String)
    case countMismatch
    case checkpointFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: transit-seed-builder <JSON directory> <output directory>"
        case let .missingCoordinate(id):
            return "Missing coordinates for \(id)"
        case let .missingStation(id):
            return "Missing station \(id)"
        case let .missingPlatform(id):
            return "Missing platform \(id)"
        case let .missingPattern(id):
            return "Missing pattern \(id)"
        case .countMismatch:
            return "The generated store did not contain the expected record counts"
        case let .checkpointFailed(message):
            return "Could not checkpoint the generated store: \(message)"
        }
    }
}
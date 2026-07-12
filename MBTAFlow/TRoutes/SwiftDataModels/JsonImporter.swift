//
//  JsonImporter.swift
//  TRoutes
//
//  Created by Adam Post on 7/2/26.
//

import Foundation
import ComposableArchitecture


actor JsonImporter {
    private let databaseClient: DatabaseClient
    private let decoder = JSONDecoder()

    init(databaseClient: DatabaseClient = .liveValue) {
        self.databaseClient = databaseClient
    }

    func importIfNeeded() async throws -> Void {
        do {
            
            var preciseTime = Date.now.formatted(
                .dateTime.hour().minute().second().secondFraction(.fractional(3))
            )
            print(preciseTime)
            let stations: [JsonBuilderStation] = try decodeJsonBuilderFile(named: "stations")
            try await databaseClient.saveImportedStations(stations)
            print("imported stations")
            
            preciseTime = Date.now.formatted(
                .dateTime.hour().minute().second().secondFraction(.fractional(3))
            )
            print(preciseTime)
            let platforms: [JsonBuilderPlatform] = try decodeJsonBuilderFile(named: "platforms")
            try await databaseClient.saveImportedPlatforms(platforms)
            print("imported platforms" )
            
            preciseTime = Date.now.formatted(
                .dateTime.hour().minute().second().secondFraction(.fractional(3))
            )
            print(preciseTime)
            let patterns: [JsonBuilderPattern] = try decodeJsonBuilderFile(named: "patterns")
            try await databaseClient.saveImportedPatterns(patterns)
            print("imported patterns")
            
           preciseTime = Date.now.formatted(
                .dateTime.hour().minute().second().secondFraction(.fractional(3))
            )
            print(preciseTime)
            let sequenceEdges: [JsonBuilderSequenceEdge] = try decodeJsonBuilderFile(named: "sequences")
            try await databaseClient.saveImportedSequenceEdges(sequenceEdges)
            print("imported edges")
            print("finished json importing")
            preciseTime = Date.now.formatted(
                .dateTime.hour().minute().second().secondFraction(.fractional(3))
            )
            print(preciseTime)
            markTransitDataImported()
            
        } catch DatabaseImportError.alreadyImported {
            markTransitDataImported()
            return
        }
    }

    private func markTransitDataImported() {
        @Shared(.isTransitDataImported) var isTransitDataImported = false
        $isTransitDataImported.withLock { $0 = true }
    }

    private func decodeJsonBuilderFile<T: Decodable>(named fileName: String) throws -> [T] {
        let url = try jsonBuilderFileURL(named: fileName)
        let data = try Data(contentsOf: url)
        return try decoder.decode([T].self, from: data)
    }

    private func jsonBuilderFileURL(named fileName: String) throws -> URL {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "json") {
            return url
        }

        if let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "json",
            subdirectory: "Resources/JsonBuilder"
        ) {
            return url
        }

        if let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "json",
            subdirectory: "JsonBuilder"
        ) {
            return url
        }

        if let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "json",
            subdirectory: "JSON"
        ) {
            return url
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceURL = repositoryURL.deletingLastPathComponent()
        let developmentURL = workspaceURL
            .appending(path: "TRoutes")
            .appending(path: "TRoutes")
            .appending(path: "Resources")
            .appending(path: "JsonBuilder")
            .appending(path: "\(fileName).json")

        if FileManager.default.fileExists(atPath: developmentURL.path) {
            return developmentURL
        }

        throw CocoaError(.fileNoSuchFile)
    }
}

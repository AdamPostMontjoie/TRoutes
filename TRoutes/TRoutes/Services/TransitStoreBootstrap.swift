//
//  TransitStoreBootstrap.swift
//  TRoutes
//
//  Created by Adam Post on 8/24/26.
//

import Foundation
import SwiftData

struct TransitStoreLocations {
    let referenceStoreURL: URL
    let userStoreURL: URL
    let manifest: TransitSeedManifest
}

enum TransitStoreBootstrap {
    private static let metadataId = "transit-reference-data"
    private static let appDataDirectoryName = "TRoutes"
    private static let referenceStorePrefix = "TransitReference-"

    static func prepareStores(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> TransitStoreLocations {
        let manifestURL = try bundledResourceURL(
            named: "TransitSeedManifest",
            extension: "json",
            bundle: bundle
        )
        let manifest = try JSONDecoder().decode(
            TransitSeedManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion == TransitDataVersion.schemaVersion,
              manifest.feedVersion == TransitDataVersion.feedVersion else {
            throw TransitStoreBootstrapError.incompatibleManifest(
                expectedSchema: TransitDataVersion.schemaVersion,
                actualSchema: manifest.schemaVersion,
                expectedFeed: TransitDataVersion.feedVersion,
                actualFeed: manifest.feedVersion
            )
        }

        let bundledStoreURL = try bundledResourceURL(
            named: (manifest.storeFileName as NSString).deletingPathExtension,
            extension: (manifest.storeFileName as NSString).pathExtension,
            bundle: bundle
        )
        let appDataDirectory = try applicationDataDirectory(fileManager: fileManager)
        let referenceDataDirectory = appDataDirectory.appending(
            path: "ReferenceData",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: referenceDataDirectory,
            withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableReferenceDataDirectory = referenceDataDirectory
        try mutableReferenceDataDirectory.setResourceValues(resourceValues)

        let safeFeedVersion = manifest.feedVersion.replacingOccurrences(of: "/", with: "-")
        let referenceStoreURL = referenceDataDirectory.appending(
            path: "\(referenceStorePrefix)\(safeFeedVersion).store"
        )
        if !fileManager.fileExists(atPath: referenceStoreURL.path) {
            let temporaryURL = appDataDirectory.appending(
                path: ".\(referenceStoreURL.lastPathComponent).\(UUID().uuidString).tmp"
            )
            try fileManager.copyItem(at: bundledStoreURL, to: temporaryURL)
            do {
                try fileManager.moveItem(at: temporaryURL, to: referenceStoreURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }

        return TransitStoreLocations(
            referenceStoreURL: referenceStoreURL,
            userStoreURL: appDataDirectory.appending(path: "UserData.store"),
            manifest: manifest
        )
    }

    static func validateReferenceStore(
        _ container: ModelContainer,
        locations: TransitStoreLocations
    ) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<TransitReferenceImportMetadata>(
            predicate: #Predicate { metadata in
                metadata.metadataId == metadataId
            }
        )
        guard let metadata = try context.fetch(descriptor).first,
              metadata.schemaVersion == locations.manifest.schemaVersion,
              metadata.feedVersion == locations.manifest.feedVersion else {
            throw TransitStoreBootstrapError.invalidStoreMetadata
        }

        guard try context.fetchCount(FetchDescriptor<TransitStation>())
                == locations.manifest.stationCount,
              try context.fetchCount(FetchDescriptor<TransitPlatform>())
                == locations.manifest.platformCount,
              try context.fetchCount(FetchDescriptor<TransitPattern>())
                == locations.manifest.patternCount,
              try context.fetchCount(FetchDescriptor<TransitSequenceEdge>())
                == locations.manifest.sequenceEdgeCount else {
            throw TransitStoreBootstrapError.invalidStoreCounts
        }
    }

    static func removeLegacyCombinedStore(
        fileManager: FileManager = .default
    ) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let legacyStoreURL = applicationSupport.appending(path: "TRoutes.store")
        for url in [
            legacyStoreURL,
            URL(fileURLWithPath: legacyStoreURL.path + "-shm"),
            URL(fileURLWithPath: legacyStoreURL.path + "-wal")
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static func removeObsoleteReferenceStores(
        keeping currentStoreURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = currentStoreURL.deletingLastPathComponent()
        let retainedURLs = [
            currentStoreURL,
            URL(fileURLWithPath: currentStoreURL.path + "-shm"),
            URL(fileURLWithPath: currentStoreURL.path + "-wal")
        ]
        let candidateDirectories = [directory, directory.deletingLastPathComponent()]

        for candidateDirectory in candidateDirectories {
            for url in try fileManager.contentsOfDirectory(
                at: candidateDirectory,
                includingPropertiesForKeys: nil
            ) where url.lastPathComponent.hasPrefix(referenceStorePrefix)
                && !retainedURLs.contains(url) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func applicationDataDirectory(
        fileManager: FileManager
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(
            path: appDataDirectoryName,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func bundledResourceURL(
        named name: String,
        extension fileExtension: String,
        bundle: Bundle
    ) throws -> URL {
        let subdirectories: [String?] = ["TransitSeed", "Resources/TransitSeed", nil]
        for subdirectory in subdirectories {
            if let url = bundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        throw TransitStoreBootstrapError.missingBundledResource(
            "\(name).\(fileExtension)"
        )
    }
}

enum TransitStoreBootstrapError: LocalizedError {
    case missingBundledResource(String)
    case incompatibleManifest(
        expectedSchema: Int,
        actualSchema: Int,
        expectedFeed: String,
        actualFeed: String
    )
    case invalidStoreMetadata
    case invalidStoreCounts

    var errorDescription: String? {
        switch self {
        case let .missingBundledResource(name):
            return "The bundled transit resource \(name) is missing."
        case let .incompatibleManifest(expectedSchema, actualSchema, expectedFeed, actualFeed):
            return "Transit seed mismatch. Expected schema \(expectedSchema) / feed \(expectedFeed), got schema \(actualSchema) / feed \(actualFeed)."
        case .invalidStoreMetadata:
            return "The installed transit store metadata is invalid."
        case .invalidStoreCounts:
            return "The installed transit store is incomplete."
        }
    }
}
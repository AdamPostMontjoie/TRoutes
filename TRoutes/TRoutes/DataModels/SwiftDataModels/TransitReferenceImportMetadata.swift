//
//  TransitReferenceImportMetadata.swift
//  TRoutes
//

import Foundation
import SwiftData

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
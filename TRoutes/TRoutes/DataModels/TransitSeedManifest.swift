//
//  TransitSeedManifest.swift
//  TRoutes
//
//  Created by Adam Post on 8/24/26.
//

struct TransitSeedManifest: Codable, Equatable {
    let schemaVersion: Int
    let feedVersion: String
    let storeFileName: String
    let storeFingerprint: String
    let stationCount: Int
    let platformCount: Int
    let patternCount: Int
    let sequenceEdgeCount: Int
}
//
//  TransitSeedManifest.swift
//  TRoutes
//

struct TransitSeedManifest: Codable, Equatable {
    let schemaVersion: Int
    let feedVersion: String
    let storeFileName: String
    let stationCount: Int
    let platformCount: Int
    let patternCount: Int
    let sequenceEdgeCount: Int
}
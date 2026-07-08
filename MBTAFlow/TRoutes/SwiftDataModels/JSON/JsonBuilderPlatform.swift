//
//  JsonBuilderPlatform.swift
//  TRoutes
//
//  Created by Adam Post on 7/2/26.
//

struct JsonBuilderPlatform: Decodable, Equatable {
    let platformId: String
    let parentId: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let monitoringMode: String
    let transitType: GTFSTransitType
    let patterns: [String]

    var stationId: String {
        parentId
    }

    var patternIds: [String] {
        patterns
    }
}

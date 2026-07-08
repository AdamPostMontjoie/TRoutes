//
//  JsonBuilderPattern.swift
//  TRoutes
//
//  Created by Adam Post on 7/2/26.
//

struct JsonBuilderPattern: Decodable, Equatable {
    let patternId: String
    let routeId: String
    let directionId: Int
    let name: String
    let typicality: Int?
    let isCanonical: Bool
    let stopCount: Int
    let isDefaultCandidate: Bool
    let defaultReason: String?
    let defaultRank: Int
    let isBranched: Bool
}

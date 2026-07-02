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
}

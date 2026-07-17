//
//  JsonBuilderSequenceEdge.swift
//  TRoutes
//
//  Created by Adam Post on 7/2/26.
//

struct JsonBuilderSequenceEdge: Decodable, Equatable {
    let routeId: String
    let patternId: String
    let directionId: Int
    let sequenceNumber: Int
    let platformId: String

    var sortIndex: Int {
        sequenceNumber
    }
}

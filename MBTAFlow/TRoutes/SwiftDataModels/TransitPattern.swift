//
//  TransitPattern.swift
//  TRoutes
//
//  Created by Adam Post on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TransitPattern {
    @Attribute(.unique) var patternId: String
    var routeId: String
    var directionId: Int
    var name: String
    var typicality: Int?
    var isCanonical: Bool
    @Relationship(deleteRule: .cascade, inverse: \TransitSequenceEdge.pattern)
    var sequenceEdges: [TransitSequenceEdge]

    init(
        patternId: String,
        routeId: String,
        directionId: Int,
        name: String,
        typicality: Int? = nil,
        isCanonical: Bool = false,
        sequenceEdges: [TransitSequenceEdge] = []
    ) {
        self.patternId = patternId
        self.routeId = routeId
        self.directionId = directionId
        self.name = name
        self.typicality = typicality
        self.isCanonical = isCanonical
        self.sequenceEdges = sequenceEdges
    }
}

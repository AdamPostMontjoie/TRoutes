//
//  UserSavedStop.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//import SwiftData
import Foundation
import SwiftData

@Model
final class UserSavedStop {
    @Attribute(.unique) var id: UUID
    var stationId: String
    var platformId: String
    var routeId: String
    var isPinned: Bool
    var addedAt: Date

    init(id: UUID = UUID(), stationId: String, platformId: String, routeId: String, isPinned: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.stationId = stationId
        self.platformId = platformId
        self.routeId = routeId
        self.isPinned = isPinned
        self.addedAt = addedAt
    }
}

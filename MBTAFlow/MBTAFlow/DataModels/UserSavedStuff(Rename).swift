//
//  Locations.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//
import Foundation

struct Stop: Codable, Equatable {
    var stopName: String
    var longitude: String
    var latitude: String
    var lastStop: Bool
}

struct RouteStruct:Equatable, Identifiable{
    var stops: [Stop]
   var id: UUID { routeId }
    var routeId: UUID
    var name:String
    var timeStamp: Date
}

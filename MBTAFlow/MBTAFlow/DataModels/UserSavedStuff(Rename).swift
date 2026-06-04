//
//  Locations.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//
import Foundation

struct Stop: Codable, Equatable,Identifiable {
    var id:UUID
    var mbtaStopId:String
    var mbtaRouteId:String
    var stopName: String
    var longitude: Double
    var latitude: Double
    var lastStop: Bool
    var address: String // display on review feature
}

struct RouteStruct:Equatable, Identifiable{
    var stops: [Stop]
    var id: UUID
    var mbtaRouteId:String
    var name:String
    var timeStamp: Date
}

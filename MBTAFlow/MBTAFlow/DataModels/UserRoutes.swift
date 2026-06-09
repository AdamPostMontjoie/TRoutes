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
    var address: String // display on review feature
    var stopType:StopType = .boardingStop //default
    var overlapsWithNext: Bool = false // Default to false
    private enum CodingKeys: String, CodingKey {
        case id
        case mbtaStopId
        case mbtaRouteId
        case stopName
        case longitude
        case latitude
        case address
    }
}

enum StopType:Codable, Equatable{
    case boardingStop
    case transferStop
    case finalStop
}

struct Leg:Equatable, Codable{
    var startStop:Stop
    var endStop:Stop
    var mbtaRouteId:String
    var transitType:TransitType
}

struct RouteStruct:Equatable, Identifiable{
    var legs:[Leg]
    var id: UUID
    var name:String
    var timeStamp: Date
}

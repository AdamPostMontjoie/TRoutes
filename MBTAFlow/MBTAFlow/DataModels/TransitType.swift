//
//  TransitType.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/30/26.
//

struct TransitRoute {
    let transitType: TransitType
    let name: String
    let direction: String
}

//some of these have branches. maybe just in direction
enum TransitType: String, Codable {
    case bus
    case greenLine
    case redLine
    case blueLine
    case orangeLine
    case heavyRail
    case silverLine
    case commuterRail
    case ferry
}

//this is how the MBTA API configures it first, maybe use?
enum RouteType: String, Codable {
    case bus
    case lightRail
    case heavyRail
    case commuterRail
    case ferry
}

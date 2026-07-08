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


// Defines the instruction for the Reducer when a user taps a transit type
enum RouteFetchStrategy {
    // For single lines. Skips Step 2, provides the exact ID needed for Step 3.
    case skipToDirection(routeId: String)
    // For groups. Tells the API what to fetch to populate Step 2.
    case fetchRoutes(filterKey: String, filterValue: String)
}



enum TransitType: String, Codable, CaseIterable {
    case redLine = "Red Line"
    case orangeLine = "Orange Line"
    case blueLine = "Blue Line"
    case mattapan = "Mattapan Trolley"
    
    case greenLine = "Green Line"
    case commuterRail = "Commuter Rail"
    case bus = "MBTA Bus"
    case ferry = "Ferry"
    
    var apiStrategy: RouteFetchStrategy {
        switch self {
        // Routes that do not require branch definition (change route ids)
        case .redLine:
            return .skipToDirection(routeId: "Red")
        case .orangeLine:
            return .skipToDirection(routeId: "Orange")
        case .blueLine:
            return .skipToDirection(routeId: "Blue")
        case .mattapan:
            return .skipToDirection(routeId: "Mattapan")
            
        // Routes that require branches to be defined
        case .greenLine:
            return .fetchRoutes(filterKey: "filter[type]", filterValue: "0")
        case .commuterRail:
            return .fetchRoutes(filterKey: "filter[type]", filterValue: "2")
        case .bus:
            return .fetchRoutes(filterKey: "filter[type]", filterValue: "3")
        case .ferry:
            return .fetchRoutes(filterKey: "filter[type]", filterValue: "4")
        }
    }
}

enum GTFSTransitType: String, Codable, Equatable {
    case bus
    case lightRail = "light rail"
    case heavyRail = "heavy rail"
    case commuterRail = "commuter rail"
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

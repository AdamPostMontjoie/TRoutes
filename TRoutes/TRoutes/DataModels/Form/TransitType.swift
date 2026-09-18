//
//  TransitType.swift
//  TRoutes
//
//  Created by Adam Post on 5/30/26.
//

enum RouteFetchStrategy {
    case skipToDirection(routeId: String)
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
        case .redLine:
            return .skipToDirection(routeId: "Red")
        case .orangeLine:
            return .skipToDirection(routeId: "Orange")
        case .blueLine:
            return .skipToDirection(routeId: "Blue")
        case .mattapan:
            return .skipToDirection(routeId: "Mattapan")
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

    /// All MBTA route IDs for this transit type (used by resolution for multi-pattern matching)
    var routeIds: [String] {
        switch self {
        case .redLine: return ["Red"]
        case .orangeLine: return ["Orange"]
        case .blueLine: return ["Blue"]
        case .mattapan: return ["Mattapan"]
        case .greenLine: return ["Green-B", "Green-C", "Green-D", "Green-E"]
        case .commuterRail, .bus, .ferry: return []
        }
    }

    var requiresRouteSelection: Bool {
        switch self {
        case .commuterRail, .bus, .ferry, .greenLine: return true
        default: return false
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .greenLine: return 0
        case .orangeLine: return 1
        case .redLine: return 2
        case .blueLine: return 3
        case .mattapan: return 4
        case .bus: return 5
        case .commuterRail: return 6
        case .ferry: return 7
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

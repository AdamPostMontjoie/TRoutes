//
//  BrancheResponse.swift
//  TRoutes
//
//  Created by Adam Post on 6/4/26.
//

// For decoding the API Response
struct RouteListResponse: Codable {
    let data: [RouteListData]
}

struct RouteListData: Codable {
    let id: String
    let attributes: RouteListAttributes
}

struct RouteListAttributes: Codable {
    let shortName: String?
    let longName: String?
    let directionNames: [String]? // e.g., ["Outbound", "Inbound"]
    let directionDestinations: [String]? // e.g., ["Boston College", "Government Center"]
}

struct TransitBranch: Codable, Equatable, Hashable {
    let id: String // e.g., "Green-B"
    let displayName: String // e.g., "B Branch"
    let directions: [TransitDirection]
}

struct TransitDirection: Codable, Equatable, Hashable {
    let directionId: Int
    let directionName: String // "Outbound"
    let destination: String // "Boston College"
}

//
//  JsonBuilderStation.swift
//  TRoutes
//
//  Created by Adam Post on 7/2/26.
//

struct JsonBuilderStation: Decodable, Equatable {
    let stationId: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let municipality: String?
    let platforms: [String]

    var platformIds: [String] {
        platforms
    }
}

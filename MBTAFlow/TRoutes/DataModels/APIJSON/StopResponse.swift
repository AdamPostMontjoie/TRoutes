//
//  StopResponse.swift
//  TRoutes
//
//  Created by Adam Post on 6/4/26.
//

struct StopListResponse: Codable {
    let data: [StopData]
}

struct StopData: Codable {
    let id: String
    let attributes: StopAttributes
}

struct StopAttributes: Codable {
    let name: String?
    let latitude: Double?
    let longitude: Double?
    let address: String?
}

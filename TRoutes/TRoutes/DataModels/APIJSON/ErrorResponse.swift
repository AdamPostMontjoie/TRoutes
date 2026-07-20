//
//  ErrorResponse.swift
//  TRoutes
//
//  Created by Adam Post on 6/4/26.
//

struct MBTAErrorResponse: Codable {
    let errors: [MBTAErrorDetail]
}

struct MBTAErrorDetail: Codable {
    let detail: String?
    let status: String?
    let code: String?
}

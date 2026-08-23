//
//  StopAttributes.swift
//  TRoutes
//
//  Created by Adam Post on 8/23/26.
//

import ActivityKit
import Foundation

struct StopActivityAttributes: ActivityAttributes {
	struct ContentState: Codable, Hashable {
		let predictions: [String]
		let updatedAt: Date
	}

	let stationId: String
	let routeId: String
	let directionId: Int
	let stopName: String
	let routeBadge: String
	let routeDetail: String?
	let destination: String
	let colorHex: String
	let foregroundColorHex: String
}


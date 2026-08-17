//
//  PredictionTarget.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import Foundation

protocol PredictionTarget {
    var predictionRouteId: String { get }
    var predictionStopIds: [String] { get }
    var predictionDirectionId: Int { get }
}

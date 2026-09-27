//
//  TransitCountdown.swift
//  TRoutes
//

import Foundation

/// Whole-minute countdown shared by prediction displays and notifications.
enum TransitCountdown {
    static func minutes(until event: Date, from now: Date) -> Int {
        max(0, Int((event.timeIntervalSince(now) / 60).rounded(.toNearestOrAwayFromZero)))
    }
}

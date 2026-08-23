//
//  MBTAUIExtensions.swift
//  TRoutes
//
//  Created by Adam Post on 7/11/26.
//

import SwiftUI

extension TransitType {
    var color: Color {
        switch self {
        case .redLine, .mattapan:
            return Color(hex: "#FF3B30") // Vibrant Red
        case .orangeLine:
            return Color(hex: "#FF9500") // Vibrant Orange
        case .blueLine:
            return Color(hex: "#007AFF") // Vibrant Blue
        case .greenLine:
            return Color(hex: "#34C759") // Vibrant Green
        case .bus:
            return Color(hex: "#FFCC00") // Vibrant Yellow
        case .commuterRail:
            return Color(hex: "#AF52DE") // Vibrant Purple
        case .ferry:
            return Color(hex: "#32ADE6") // Vibrant Cyan
        }
    }
    
    var iconName: String {
        switch self {
        case .redLine, .orangeLine, .blueLine:
            return "train.side.front.car"
        case .greenLine, .mattapan:
            return "tram.fill"
        case .bus:
            return "bus.fill"
        case .commuterRail:
            return "train.side.front.car"
        case .ferry:
            return "ferry.fill"
        }
    }
}

extension Color {
    var isLightBackground: Bool {
        // Simple heuristic: bus yellow and silver line are light, others are dark
        self == TransitType.bus.color || self == Color(hex: "#7C878E")
    }
}

// Helper to init Color from hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

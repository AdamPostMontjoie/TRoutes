
//
//  RoutePresentation.swift
//  TRoutes
//

import Foundation

struct RoutePresentation: Equatable {
    let badgeText: String
    let detailText: String?

    init(routeId: String, transitType: TransitType) {
        switch transitType {
        case .redLine:
            self.badgeText = routeId == "Mattapan" ? "M" : "RL"
            self.detailText = nil
        case .orangeLine:
            self.badgeText = "OL"
            self.detailText = nil
        case .blueLine:
            self.badgeText = "BL"
            self.detailText = nil
        case .greenLine:
            self.badgeText = "GL"
            self.detailText = nil
        case .mattapan:
            self.badgeText = "M"
            self.detailText = nil
        case .commuterRail:
            self.badgeText = "CR"
            self.detailText = Self.commuterRailName(for: routeId)
        case .bus:
            self.badgeText = Self.busBadge(for: routeId)
            self.detailText = nil
        case .ferry:
            self.badgeText = routeId.hasPrefix("Boat-")
                ? String(routeId.dropFirst("Boat-".count))
                : routeId
            self.detailText = nil
        }
    }

    private static func busBadge(for routeId: String) -> String {
        switch routeId {
        case "741": return "SL1"
        case "742": return "SL2"
        case "743": return "SL3"
        case "751": return "SL4"
        case "749": return "SL5"
        case "746": return "SLW"
        default: return routeId
        }
    }

    private static func commuterRailName(for routeId: String) -> String {
        switch routeId {
        case "CR-Fairmount": return "Fairmount"
        case "CR-Fitchburg": return "Fitchburg"
        case "CR-Foxboro": return "Foxboro"
        case "CR-Franklin": return "Franklin/Foxboro"
        case "CR-Greenbush": return "Greenbush"
        case "CR-Haverhill": return "Haverhill"
        case "CR-Kingston": return "Kingston"
        case "CR-Lowell": return "Lowell"
        case "CR-Needham": return "Needham"
        case "CR-NewBedford": return "Fall River/New Bedford"
        case "CR-Newburyport": return "Newburyport/Rockport"
        case "CR-Providence": return "Providence/Stoughton"
        case "CR-Worcester": return "Framingham/Worcester"
        default:
            return routeId.hasPrefix("CR-")
                ? String(routeId.dropFirst("CR-".count))
                : routeId
        }
    }
}

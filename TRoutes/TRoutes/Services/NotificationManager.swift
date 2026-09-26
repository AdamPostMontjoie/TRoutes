//
//  NotificationManager.swift
//  TRoutes
//
//  Created by Adam Post on 9/20/26.
//
import ComposableArchitecture
import Foundation

enum JourneyNotificationIntent: Equatable, Sendable {
    case departureRecommendation(BoardingNoticeDetails, isSingleLine: Bool)
    case transferApproaching(UpcomingArrivalNoticeDetails)
    case transferNow(BoardingNoticeDetails)
    case destinationNext(UpcomingArrivalNoticeDetails)
    case arrivedAtDestination(String)
    case connectionWarningChanged(ConnectionWarningChangedDetails)
    case missedVehicle(BoardingNoticeDetails)
    case trackingDegraded
}

actor NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    @Dependency(\.notificationsClient) var notificationsClient

    func createNotification(intent: JourneyNotificationIntent) async {
        let message: String
        let title:String
        let isTimeSensitive: Bool
        switch intent {
        case let .departureRecommendation(details, isSingleLine):
            title = isSingleLine ? "Departure" : "Recommendation"
            message = boardingMessage(details, isRecommendation: true)
            isTimeSensitive = false
        case let .transferApproaching(details):
            title = "Approaching Transfer"
            message = transferApproachingMessage(details)
            isTimeSensitive = true
        case let .transferNow(details):
            title = "Transfer Now!"
            message = boardingMessage(details, isRecommendation: false)
            isTimeSensitive = true
        case let .destinationNext(details):
            title = "Approaching Destination"
            message = destinationNextMessage(details)
            isTimeSensitive = true
        case let .arrivedAtDestination(destinationName):
            title = "Arrived At Destination"
            message = "You have arrived at \(destinationName)."
            isTimeSensitive = false
        case let .connectionWarningChanged(details):
            title = "Warning"
            message = connectionWarningChangedMessage(details)
            isTimeSensitive = true
        case let .missedVehicle(details):
            let service = serviceDescription(
                routeId: details.routeId,
                transitType: details.transitType,
                directionDestination: details.directionDestination
            )
            title = "Missed"
            message = "Looks like you missed the \(service) at \(details.boardingStopName). Recalculating your departure and ETA."
            isTimeSensitive = false
        case .trackingDegraded:
            title = "Error"
            message = "GPS signal was lost or is inaccurate. Journey tracking may be degraded."
            isTimeSensitive = false
        }

        await notificationsClient.userNotification(title, message, isTimeSensitive)
    }

    private func boardingMessage(_ details: BoardingNoticeDetails, isRecommendation: Bool) -> String {
        let service = serviceDescription(
            routeId: details.routeId,
            transitType: details.transitType,
            directionDestination: details.directionDestination
        )
        var message: String

        if isRecommendation {
            message = "Board the \(service) at \(details.boardingStopName)."
        } else if let previousStopName = details.previousStopName,
                  previousStopName != details.boardingStopName {
            message = "Transfer to \(details.boardingStopName) for the \(service)."
        } else {
            message = "Transfer to the \(service)."
        }

        if let timing = timingDescription(details.boardingTime) {
            message += " \(sentence(timing))."
        }
        return appendingWarning(details.connectionWarning, to: message)
    }

    private func transferApproachingMessage(_ details: UpcomingArrivalNoticeDetails) -> String {
        var message = "Your transfer at \(details.stopName) is the next stop."
        if let arrival = details.arrival {
            message += " Expected arrival \(relativeDescription(for: arrival))."
        }

        if let transferRouteId = details.transferRouteId,
           let transferTransitType = details.transferTransitType {
            let service = serviceDescription(
                routeId: transferRouteId,
                transitType: transferTransitType,
                directionDestination: nil
            )
            if let transferStopName = details.transferStopName,
               transferStopName != details.stopName {
                message += " Transfer to \(transferStopName) for the \(service) when you arrive."
            } else {
                message += " Transfer to the \(service) when you arrive."
            }
        }

        return appendingWarning(details.connectionWarning, to: message)
    }

    private func destinationNextMessage(_ details: UpcomingArrivalNoticeDetails) -> String {
        var message = "Your destination, \(details.stopName), is next."
        if let arrival = details.arrival {
            message += " Expected arrival \(relativeDescription(for: arrival))."
        }
        return message
    }

    private func connectionWarningChangedMessage(_ details: ConnectionWarningChangedDetails) -> String {
        let service = connectionServiceDescription(details)
        let recovered: Bool
        if let previousWarning = details.previousWarning,
           let warning = details.warning {
            recovered = warning.notificationUrgency < previousWarning.notificationUrgency
        } else {
            recovered = false
        }

        if recovered {
            var message = "Your connection to the \(service) is possible again."
            if let boarding = timingDescription(details.boardingTime) {
                message += " \(sentence(boarding))."
            }
            if let destinationArrival = details.destinationArrival {
                message += " Expected arrival at \(clockDescription(for: destinationArrival))."
            }
            return message
        }

        guard let warning = details.warning else {
            return "Your connection to the \(service) has improved."
        }

        switch warning {
        case .tight:
            var message = "Your connection to the \(service) is now tight."
            if let boarding = timingDescription(details.boardingTime) {
                message += " \(sentence(boarding))."
            }
            return message

        case .highConsequence:
            return "Your connection to the \(service) has a long wait before the next service."

        case .tightHighConsequence:
            var message = "Move quickly for the \(service). This connection is tight, and missing it means a long wait."
            if let boarding = timingDescription(details.boardingTime) {
                message += " \(sentence(boarding))."
            }
            return message

        case .likelyMiss:
            var message = "You’re unlikely to make the \(service)"
            if let previousBoarding = timingDescription(details.previousBoardingTime) {
                message += " \(previousBoarding)."
            } else {
                message += "."
            }

            if details.journeyRemainsPossible {
                if let replacementBoarding = timingDescription(details.boardingTime) {
                    message += " Your ETA now uses the \(service) \(replacementBoarding)."
                }
                if let destinationArrival = details.destinationArrival {
                    message += " Expected arrival at \(clockDescription(for: destinationArrival))."
                }
            } else {
                message += " An updated ETA isn’t available yet."
            }
            return message

        case .none:
            return "Your connection to the \(service) has improved."
        }
    }

    private func timingDescription(_ selectedTime: SelectedStopTime?) -> String? {
        guard let selectedTime else { return nil }

        switch (selectedTime.event, selectedTime.source) {
        case (.arrival, .prediction):
            return "arriving \(relativeDescription(for: selectedTime.time))"
        case (.departure, .prediction):
            return "expected to depart \(relativeDescription(for: selectedTime.time))"
        case (.arrival, .schedule):
            return "scheduled to arrive at \(clockDescription(for: selectedTime.time))"
        case (.departure, .schedule):
            return "scheduled to depart at \(clockDescription(for: selectedTime.time))"
        }
    }

    private func serviceDescription(routeId: String, transitType: TransitType, directionDestination: String?) -> String {
        let route = RoutePresentation(routeId: routeId, transitType: transitType)
        let base: String

        switch transitType {
        case .redLine, .orangeLine, .blueLine:
            base = "\(transitType.rawValue) train"
        case .mattapan:
            base = "Mattapan trolley"
        case .greenLine:
            let branch = routeId.hasPrefix("Green-")
                ? String(routeId.dropFirst("Green-".count))
                : ""
            base = branch.isEmpty
                ? "Green Line train"
                : "Green Line \(branch) train"
        case .commuterRail:
            base = "\(route.detailText ?? routeId) Line train"
        case .bus:
            base = "Route \(route.badgeText) bus"
        case .ferry:
            base = "\(route.detailText ?? route.badgeText) ferry"
        }

        guard let directionDestination, !directionDestination.isEmpty else {
            return base
        }
        return "\(base) toward \(directionDestination)"
    }

    private func connectionServiceDescription(_ details: ConnectionWarningChangedDetails) -> String {
        guard let routeId = details.departingRouteId,
              let transitType = details.transitType else {
            return "connecting service"
        }
        let service = serviceDescription(
            routeId: routeId,
            transitType: transitType,
            directionDestination: nil
        )
        guard let stopName = details.stopName else { return service }
        return "\(service) at \(stopName)"
    }

    private func appendingWarning(_ warning: ConnectionWarning, to message: String) -> String {
        switch warning {
        case .none, .tight, .highConsequence:
            return message
        case .tightHighConsequence:
            return "\(message) There may be a tight connection, and missing it means a long wait."
        case .likelyMiss:
            return "\(message) You’re unlikely to make this connection."
        }
    }

    private func relativeDescription(for date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSinceNow / 60))
        if minutes <= 0 {
            return "now"
        }
        if minutes == 1 {
            return "in 1 minute"
        }
        return "in \(minutes) minutes"
    }

    private func clockDescription(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

//
//  NotificationManager.swift
//  TRoutes
//
//  Created by Adam Post on 9/20/26.
//
import ComposableArchitecture
import Foundation

enum JourneyNotificationIntent: Equatable, Sendable {
    case departureRecommendation(BoardingNoticeDetails)
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
        switch intent {
        case let .departureRecommendation(details):
            title = "Departure"
            message = boardingMessage(details, isRecommendation: true)
        case let .transferApproaching(details):
            title = "Approaching Transfer"
            message = transferApproachingMessage(details)
        case let .transferNow(details):
            title = "Transfer Now!"
            message = boardingMessage(details, isRecommendation: false)
        case let .destinationNext(details):
            title = "Approaching Destination"
            message = destinationNextMessage(details)
        case let .arrivedAtDestination(destinationName):
            title = "Arrived At Destination"
            message = "You have arrived at \(destinationName)."
        case let .connectionWarningChanged(details):
            title = "Warning"
            message = connectionWarningChangedMessage(details)
        case let .missedVehicle(details):
            let service = serviceDescription(
                routeId: details.routeId,
                transitType: details.transitType,
                directionDestination: details.directionDestination
            )
            title = "Missed"
            message = "Looks like you missed the \(service) at \(details.boardingStopName). Recalculating your departure and ETA."
        case .trackingDegraded:
            title = "Error"
            message = "GPS signal was lost or is inaccurate. Journey tracking may be degraded."
        }

        await notificationsClient.userNotification(title, message)
    }

    private func boardingMessage(_ details: BoardingNoticeDetails, isRecommendation: Bool) -> String {
        let service = serviceDescription(
            routeId: details.routeId,
            transitType: details.transitType,
            directionDestination: details.directionDestination
        )
        var message: String

        if isRecommendation {
            message = "Recommendation: Board the \(service) at \(details.boardingStopName)."
        } else if let previousStopName = details.previousStopName,
                  previousStopName != details.boardingStopName {
            message = "Transfer to \(details.boardingStopName) for the \(service)."
        } else {
            message = "Transfer to the \(service)."
        }

        if let timing = boardingTimingDescription(details) {
            message += " \(sentence(timing))."
        }
        return appendingWarning(details.connectionWarning, to: message)
    }

    private func transferApproachingMessage(_ details: UpcomingArrivalNoticeDetails) -> String {
        var message: String
        if let arrival = details.arrival {
            message = "Arrive at \(details.stopName) \(relativeDescription(for: arrival))."
        } else {
            message = "\(details.stopName) is the next stop."
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
            if let departure = timingDescription(details.departure, event: .departure) {
                message += " \(sentence(departure))."
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
            if let departure = timingDescription(details.departure, event: .departure) {
                message += " \(sentence(departure))."
            }
            return message

        case .highConsequence:
            return "Your connection to the \(service) has a long wait before the next service."

        case .tightHighConsequence:
            var message = "Move quickly for the \(service). This connection is tight, and missing it means a long wait."
            if let departure = timingDescription(details.departure, event: .departure) {
                message += " \(sentence(departure))."
            }
            return message

        case .likelyMiss:
            var message = "You’re unlikely to make the \(service)"
            if let oldDeparture = timingDescription(details.oldTime, event: .departure) {
                message += " \(oldDeparture)."
            } else {
                message += "."
            }

            if details.journeyRemainsPossible {
                if let replacementDeparture = timingDescription(details.departure, event: .departure) {
                    message += " Your ETA now uses the \(service) \(replacementDeparture)."
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

    private func boardingTimingDescription(_ details: BoardingNoticeDetails) -> String? {
        if let arrival = timingDescription(details.arrivalTime, event: .arrival) {
            return arrival
        }
        return timingDescription(details.departureTime, event: .departure)
    }

    private func timingDescription(_ noticeTime: NoticeTime?, event: TimingEvent) -> String? {
        guard let time = noticeTime?.time else { return nil }

        switch (event, noticeTime?.source) {
        case (.arrival, .prediction):
            return "arriving \(relativeDescription(for: time))"
        case (.departure, .prediction):
            return "expected to depart \(relativeDescription(for: time))"
        case (.arrival, .schedule):
            return "scheduled to arrive at \(clockDescription(for: time))"
        case (.departure, .schedule):
            return "scheduled to depart at \(clockDescription(for: time))"
        case (.arrival, nil):
            return "arriving at \(clockDescription(for: time))"
        case (.departure, nil):
            return "departing at \(clockDescription(for: time))"
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
        case .none:
            return message
        case .tight:
            return "\(message) This connection may be tight."
        case .highConsequence:
            return "\(message) The next service is much later."
        case .tightHighConsequence:
            return "\(message) This connection may be tight, and missing it means a long wait."
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

    private enum TimingEvent {
        case arrival
        case departure
    }
}

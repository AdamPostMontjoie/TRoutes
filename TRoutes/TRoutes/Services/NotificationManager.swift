//
//  NotificationManager.swift
//  TRoutes
//
//  Created by Adam Post on 9/20/26.
//
import ComposableArchitecture

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
    
    func createNotification(intent:JourneyNotificationIntent) async {
        switch intent {
        case .departureRecommendation(let boardingNoticeDetails):
            <#code#>
        case .transferApproaching(let arrivalNoticeDetails):
            <#code#>
        case .transferNow(let boardingNoticeDetails):
            <#code#>
        case .destinationNext(let arrivalNoticeDetails):
            <#code#>
        case .arrivedAtDestination(let string):
            await notificationsClient.userNotification(string)
        case .connectionWarningChanged(let connectionWarningNoticeDetails):
            <#code#>
        case .missedVehicle(let boardingNoticeDetails):
            
        case .trackingDegraded:
            <#code#>
            
        }
    }
    
}

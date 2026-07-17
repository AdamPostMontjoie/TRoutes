//
//  NotificationsClient.swift
//  TRoutes
//
//  Created by Adam Post on 6/16/26.
//

import ComposableArchitecture
import Foundation
import UserNotifications
import UIKit

struct NotificationsClient {
    var requestAuthorization: @Sendable () async -> Void
    var debugNotification: @Sendable (String) async -> Void
    var userNotification:@Sendable (String) async -> Void
}

extension NotificationsClient: DependencyKey {
    static let liveValue = Self(
        requestAuthorization: {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("Failed to request notification authorization: \(error)")
            }
        },
        debugNotification: { log in
            guard DebugAvailability.isDebugActive else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "T Routes Debug"
            content.body = log
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to fire debug notif: \(error)")
            }
        },
        userNotification: { message in
            guard !DebugAvailability.isDebugActive else {
                return
            }

            guard await UIApplication.shared.applicationState == .background else {
                return
            }
            
            // Construct and present the user-facing alert notification
            let content = UNMutableNotificationContent()
            content.title = "T Routes"
            content.body = message
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to fire user notif: \(error)")
            }
        }
    )
}


extension DependencyValues {
    var notificationsClient: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    
    // This function intercepts the notification right before it displays
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Force iOS to show the banner and play the sound even if the app is foregrounded
        completionHandler([.banner, .sound])
    }
}

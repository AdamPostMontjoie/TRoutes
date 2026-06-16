//
//  NotificationDelegate.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/16/26.
//

import UserNotifications

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

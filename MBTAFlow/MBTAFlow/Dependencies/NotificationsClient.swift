//
//  NotificationsClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/16/26.
//

import ComposableArchitecture
import UserNotifications

struct NotificationsClient {
    var requestAuthorization: @Sendable () async -> Void
    var debugStringNotification: @Sendable (String) async -> Void
    var setDevMode: @Sendable (Bool) -> Void
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
        debugStringNotification: { log in
            guard UserDefaults.standard.bool(forKey: "enableDebugNotifications") else {
                print("🔕 Debug Notif Suppressed: \(log)")
                return
            }
            print("sening notification")
            
            // 2. Construct the payload
            let content = UNMutableNotificationContent()
            content.title = "MBTAFlow Debug"
            content.body = log
            content.sound = .default
            
            // 3. nil trigger guarantees immediate delivery
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("🔔 Debug Notif Fired: \(log)")
            } catch {
                print("❌ Failed to fire debug notif: \(error)")
            }
        },
        setDevMode: { enabled in
            UserDefaults.standard.set(enabled, forKey: "enableDebugNotifications")
        }
    )

    static let testValue: Self = .liveValue
}


extension DependencyValues {
    var notificationsClient: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}

//
//  MBTAFlowApp.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/23/26.
//

import SwiftUI
import ComposableArchitecture
import SwiftData
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        guard launchOptions?[.location] != nil else {
            print("non location launch")
            return true
        }
        print("location launch")
        let regionManager = RegionManager.shared
        regionManager.fireDebugNotif = NotificationsClient.liveValue.debugStringNotification
        regionManager.handleLocationLaunch()
        
        return true
    }
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task {
            await NotificationsClient.liveValue.debugStringNotification("Memory warning received")
        }
    }
    func applicationWillTerminate(_ application: UIApplication) {
        Task {
            await NotificationsClient.liveValue.debugStringNotification("App will terminate")
        }
    }
}

@main
struct MBTAFlow: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let notificationDelegate = NotificationDelegate()
        
    init() {
        // Attach the delegate on boot
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UserDefaults.standard.set(true, forKey: "enableDebugNotifications")
    }
    
    static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
      }
    
    var body: some Scene {
        WindowGroup {
            RootView(store:MBTAFlow.store)
        }
    }
}


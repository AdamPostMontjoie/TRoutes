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
        
        
        //region manager just needs to be created for it to handle did enter did exit
        let regionManager = RegionManager.shared
        //this needs to be removed later
        regionManager.fireDebugNotif = NotificationsClient.liveValue.debugStringNotification
        //put this before or after the region manager creation?
        Task {
            await JourneyEngine.shared.startListeningToLocationEvents()
        }
        
        //may need to ensure stream is being listened to
        
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
struct TRoutes: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let notificationDelegate = NotificationDelegate()
        
    init() {
        // Attach the delegate on boot
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UserDefaultsClient.liveValue.setDebugNotifications(true)
    }
    
    static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
      }
    
    var body: some Scene {
        WindowGroup {
            RootView(store:TRoutes.store)
        }
    }
}


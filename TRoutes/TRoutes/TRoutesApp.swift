//
//  TRoutesApp.swift
//  TRoutes
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
        //put this before or after the region manager creation?
        Task {
            try await JsonImporter().importIfNeeded()
            await JourneyEngine.shared.restoreActiveJourneyIfNeeded()
        }
        
        //may need to ensure stream is being listened to
        
        return true
    }
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task {
            await NotificationsClient.liveValue.debugNotification("Memory warning received")
        }
    }
    func applicationWillTerminate(_ application: UIApplication) {
        Task {
            await NotificationsClient.liveValue.debugNotification("App will terminate")
        }
    }
}

//application wide state
@Observable class AppState {
    
}

@main
struct TRoutes: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let notificationDelegate = NotificationDelegate()
        
    init() {
        // Attach the delegate on boot
        UNUserNotificationCenter.current().delegate = notificationDelegate
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

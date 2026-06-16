//
//  MBTAFlowApp.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/23/26.
//

import SwiftUI
import ComposableArchitecture
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        return true
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


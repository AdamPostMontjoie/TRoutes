//
//  MBTAFlowApp.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/23/26.
//

import SwiftUI
import ComposableArchitecture
import SwiftData

@main
struct FoodSizer: App {
    
    static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
      }
    var body: some Scene {
        WindowGroup {
            RootView(store:FoodSizer.store)
        }
        .modelContainer(for: Route.self) //initializes database for app
    }
}


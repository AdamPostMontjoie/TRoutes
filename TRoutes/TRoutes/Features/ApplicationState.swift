//
//  ApplicationState.swift
//  TRoutes
//
//  Created by Adam Post on 7/7/26.
//

import ComposableArchitecture
import Foundation

@ObservableState
struct ApplicationState: Equatable {
    var isDebugAvailable = DebugAvailability.current
    @Shared(.isDebugEnabled) var isDebugEnabled = true
    @Shared(.hasValidApiKey) var hasValidApiKey = false
    var isDebugActive: Bool {
        isDebugAvailable && isDebugEnabled
    }

    var debug: DebugState {
        DebugState(
            isDebugAvailable: isDebugAvailable,
            isDebugEnabled: isDebugEnabled,
            isDebugActive: isDebugActive
        )
    }
}

struct DebugState: Equatable {
    var isDebugAvailable = false
    var isDebugEnabled = true
    var isDebugActive = false
}

enum DisplayUnits: String, CaseIterable {
    case imperial
    case metric

    var title: String {
        rawValue.capitalized
    }
}

enum DebugAvailability {
    static let isDebugEnabledStorageKey = "debugIsEnabled"
    static let isMotionEventsEnabledStorageKey = "motionEventsIsEnabled"

    static var current: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isDebugActive: Bool {
        let storedValue = UserDefaults.standard.object(forKey: isDebugEnabledStorageKey) as? Bool
        return current && (storedValue ?? true)
    }
}

extension SharedReaderKey where Self == AppStorageKey<Bool> {
    static var isDebugEnabled: Self {
        appStorage(DebugAvailability.isDebugEnabledStorageKey)
    }
    static var isMotionEventsEnabled: Self {
        appStorage(DebugAvailability.isMotionEventsEnabledStorageKey)
    }
    static var hasOnboarded: Self {
        appStorage("hasOnboarded")
    }
    static var hasValidApiKey: Self {
        appStorage("hasValidApiKey")
    }
}

extension SharedReaderKey where Self == AppStorageKey<String> {
    static var displayUnits: Self {
        appStorage("displayUnits")
    }
    static var mbtaApiKey: Self {
        appStorage("mbtaApiKey")
    }
}

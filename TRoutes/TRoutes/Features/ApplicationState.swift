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

enum DebugAvailability {
    static let isDebugEnabledStorageKey = "debugIsEnabled"

    static var current: Bool {
        #if DEBUG
        return true
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return true
        }
        return receiptURL.lastPathComponent == "sandboxReceipt"
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
    static var hasOnboarded: Self {
        appStorage("hasOnboarded")
    }
    static var isTransitDataImported: Self {
        appStorage("transitDataImported")
    }
}

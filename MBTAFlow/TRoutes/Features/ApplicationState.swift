//
//  ApplicationState.swift
//  TRoutes
//
//  Created by Adam Post on 7/7/26.
//

import ComposableArchitecture

@ObservableState
struct ApplicationState: Equatable {
    var isDebugAvailable = DebugAvailability.current
    @Shared(.isDebugEnabled) var isDebugEnabled = false

    var debug: DebugState {
        DebugState(
            isDebugAvailable: isDebugAvailable,
            isDebugEnabled: isDebugEnabled
        )
    }
}

struct DebugState: Equatable {
    var isDebugAvailable = false
    var isDebugEnabled = false
}

enum DebugAvailability {
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
}

extension SharedReaderKey where Self == AppStorageKey<Bool> {
    static var isDebugEnabled: Self {
        appStorage("debug.isEnabled")
    }
}

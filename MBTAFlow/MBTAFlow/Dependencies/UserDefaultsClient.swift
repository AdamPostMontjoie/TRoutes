//
//  UserDefaultsClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/17/26.
//

import ComposableArchitecture
import Foundation

struct UserDefaultsClient {
    var saveActiveJourney: @Sendable (JourneyState) -> Void
    var loadActiveJourney: @Sendable () -> JourneyState?
    var clearActiveJourney: @Sendable () -> Void
    
    var setDebugNotifications: @Sendable (Bool) -> Void
    var areDebugNotificationsEnabled: @Sendable () -> Bool
}

extension UserDefaultsClient: DependencyKey {
    static let liveValue: Self = {
        let suiteName = "group.com.adampost.MBTAFlow"
        let activeJourneyStateKey = "activeJourneyState"
        let debugNotificationsKey = "enableDebugNotifications"

        return Self(
            saveActiveJourney: { state in
                guard let encoded = try? JSONEncoder().encode(state) else {
                    return
                }

                UserDefaults(suiteName: suiteName)?.set(encoded, forKey: activeJourneyStateKey)
            },
            loadActiveJourney: {
                guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: activeJourneyStateKey),
                      let state = try? JSONDecoder().decode(JourneyState.self, from: data) else {
                    return nil
                }
                return state
            },
            clearActiveJourney: {
                UserDefaults(suiteName: suiteName)?.removeObject(forKey: activeJourneyStateKey)
            },
            setDebugNotifications: { enabled in
                UserDefaults.standard.set(enabled, forKey: "enableDebugNotifications")
            },
            areDebugNotificationsEnabled: {
                return UserDefaults.standard.bool(forKey: "enableDebugNotifications")
            }
        )
    }()

    static let testValue = Self(
        saveActiveJourney: { _ in },
        loadActiveJourney: { nil },
        clearActiveJourney: { },
        setDebugNotifications: { _ in },
        areDebugNotificationsEnabled: {false}
    )
}

extension DependencyValues {
    var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}

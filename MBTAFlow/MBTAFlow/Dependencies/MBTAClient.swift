//
//  MBTAClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture

//this will fetch whatever route times we need once we either A. Start a route B. Enter step location
struct MBTAClient {
    var fetchTransitTimes: @Sendable (String) -> String
}

extension MBTAClient:DependencyKey {
    static let liveValue = Self (
        fetchTransitTimes: { word in
            return word
        }
    )
    static let testValue: Self = .liveValue //TODO figure out what the hell this is even about
}

extension DependencyValues {
    var mbtaClient: MBTAClient {
        get { self[MBTAClient.self] }
        set { self[MBTAClient.self] = newValue }
    }
}

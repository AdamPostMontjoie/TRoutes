//
//  LocationAlertFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/14/26.
//

import ComposableArchitecture
import Foundation

enum LocationAlertMode:Equatable {
    case firstTime
    case changeSettings
    case routeInterrupted
}

@Reducer
struct LocationAlertFeature {
    @ObservableState
    struct State: Equatable {
        var mode: LocationAlertMode
    }

    enum Action: Equatable {
        
        case continueButtonTapped
        case settingsButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)
        enum Delegate: Equatable {
            case requestPermissionsInApp
            case openSettings
            case cancel
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .continueButtonTapped:
                return .send(.delegate(.requestPermissionsInApp))
            case .settingsButtonTapped:
                return .send(.delegate(.openSettings))
            case .cancelButtonTapped:
                return .send(.delegate(.cancel))
            case .delegate:
                return .none
            }
        }
    }
}


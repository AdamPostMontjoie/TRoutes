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
}

@Reducer
struct LocationAlertFeature {
    @ObservableState
    struct State: Equatable {
        var mode: LocationAlertMode
    }

    enum Action: Equatable {
        
        enum Delegate: Equatable {
            case editLeg(Leg)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            
            }
        }
    }
}


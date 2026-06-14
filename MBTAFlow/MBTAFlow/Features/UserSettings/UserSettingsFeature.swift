//
//  UserSettingsFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/14/26.
//
import ComposableArchitecture

@Reducer
struct UserSettingsFeature {
    @ObservableState
    struct State: Equatable {
        
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

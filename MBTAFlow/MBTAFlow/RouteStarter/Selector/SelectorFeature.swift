//
//  SelectorFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct SelectorFeature {
    struct SelectorItem: Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    @ObservableState
    struct State: Equatable {
        var items = [
            SelectorItem(id: UUID(), name: "Red Line"),
            SelectorItem(id: UUID(), name: "Orange Line"),
            SelectorItem(id: UUID(), name: "Green Line"),
            SelectorItem(id: UUID(), name: "Blue Line")
        ]
    }
    
    enum Action: Equatable {
        case selected
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selected:
                return .none
            }
        }
    }
}

//
//  StopRowFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//
import ComposableArchitecture
import Foundation

@Reducer
struct StopRowFeature {
    @ObservableState
    struct State: Equatable, Identifiable{
        var stop: Stop
        var id: UUID { stop.id }
        var editStopPresented: Bool = false
    }
    enum Action:Equatable {
        case editStopButtonTapped // this wil bring up a step of the createrouteform, need to modularize
        case deleteStopButtonTapped //removes this stop from the route
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case deleteStop
            case stopUpdated(Stop)
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .editStopButtonTapped:
                // raise the stop picker from createroutefeature, modularize
                state.editStopPresented = true
                return .none
            
            case .deleteStopButtonTapped:
                return .send(.delegate(.deleteStop))
            case .delegate:
                return .none
            }
        }

    }
}

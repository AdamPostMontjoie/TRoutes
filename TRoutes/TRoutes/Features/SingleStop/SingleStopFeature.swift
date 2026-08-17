//
//  SingleStopFeature.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import ComposableArchitecture

@Reducer
struct SingleStopFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.hasValidApiKey) var hasValidApiKey = false
        @Presents var destination: Destination.State?
    }
    
    enum Action: Equatable {
        case apiKeyLinkTapped
        case onSettingsButtonTapped
        case destination(PresentationAction<Destination.Action>)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .apiKeyLinkTapped:
                state.destination = .apiKeyAlert(ApiKeyAlertFeature.State())
                return .none
                
            case .onSettingsButtonTapped:
                state.destination = .userSettings(UserSettingsFeature.State())
                return .none
                
            case .destination(.presented(.apiKeyAlert(.delegate(.dismiss)))):
                state.destination = nil
                return .none
                
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension SingleStopFeature {
    @Reducer
    enum Destination {
        case apiKeyAlert(ApiKeyAlertFeature)
        case userSettings(UserSettingsFeature)
    }
}

extension SingleStopFeature.Destination.State: Equatable {}
extension SingleStopFeature.Destination.Action: Equatable {}


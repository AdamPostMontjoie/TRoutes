//
//  LegFormFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/12/26.
//

import ComposableArchitecture
import Dependencies
import Foundation

enum LegFormMode: Equatable {
    case create
    case edit
}

@Reducer
struct LegFormFeature {
    private enum ResetScope {
        case type
        case branch
        case direction
        case startStop
    }
    private func reset(_ scope: ResetScope, state: inout State) {
        switch scope {
        case .type:
            state.selectedType = nil
            state.selectedBranch = nil
            state.branchOptions = nil
            state.selectedDirection = nil
            state.directionOptions = nil
            state.stopOptions = []
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.mbtaRouteId = nil
            state.currentLeg = nil
            state.currentFormStep = .selectType
            state.hasHydratedEditOptions = false

        case .branch:
            state.selectedBranch = nil
            state.selectedDirection = nil
            state.directionOptions = nil
            state.stopOptions = []
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.mbtaRouteId = nil
            state.currentLeg = nil
            state.currentFormStep = .selectBranch
            state.hasHydratedEditOptions = false

        case .direction:
            state.selectedDirection = nil
            state.stopOptions = []
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.currentLeg = nil
            state.currentFormStep = .selectDirection
            state.hasHydratedEditOptions = false

        case .startStop:
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.currentLeg = nil
            state.currentFormStep = .selectStartStop
        }
    }
    @ObservableState
    struct State: Equatable {
        var mode: LegFormMode

        var typeOptions: [TransitType] = TransitType.allCases
        var selectedType: TransitType?
        var branchOptions: [TransitBranch]?
        var selectedBranch: TransitBranch?
        var directionOptions: [TransitDirection]?
        var selectedDirection: TransitDirection?
        var stopOptions: [Stop] = []
        var selectedStartStop: Stop?
        var selectedEndStop: Stop?
        var mbtaRouteId: String?
        var currentFormStep: FormStep = .selectType
        var currentLeg: Leg?
        
        var hasHydratedEditOptions = false

        @Presents var destination: Destination.State?

        init(mode: LegFormMode = .create, leg: Leg? = nil) {
            self.mode = mode
            
            //populates form if edit mode
            guard let leg else { return }

            self.selectedType = leg.transitType
            self.selectedStartStop = leg.startStop
            self.selectedEndStop = leg.endStop
            self.mbtaRouteId = leg.mbtaRouteId
            self.currentLeg = leg
            self.currentFormStep = .selectEndStop

            self.selectedBranch = leg.transitBranch
            self.branchOptions = leg.transitBranch.map { [$0] }
            self.selectedDirection = leg.transitDirection
            self.directionOptions = leg.transitDirection.map { [$0] }
            self.stopOptions = [leg.startStop, leg.endStop]
        }
    }

    enum Action: Equatable {
        case transitTypeSelected(TransitType)
        case branchesLoaded([TransitBranch])
        case branchSelected(TransitBranch)
        case directionsLoaded([TransitDirection])
        case directionSelected(TransitDirection, String)
        case stopsLoaded([Stop])
        case editOptionsHydrated([Stop])
        case startStopSelected(Stop)
        case endStopSelected(Stop)

        case buildLeg

        case resetTypeSelection
        case resetBranchSelection
        case resetDirectionSelection
        case resetStartStopSelection

        case onAppear

        case primaryButtonTapped
        case saveButtonTapped
        case closeButtonTapped
        case apiFailure

        case destination(PresentationAction<Destination.Action>)

        enum Alert: Equatable {
            case apiFailure
        }

        case delegate(Delegate)

        enum Delegate: Equatable {
            case addAnotherLeg(Leg)
            case completeRoute(Leg)
            case saveEditedLeg(Leg)
            case requestDismissal
        }
    }

    @Dependency(\.mbtaClient) var mbtaClient: MBTAClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .closeButtonTapped:
                return .send(.delegate(.requestDismissal))

            case .onAppear:
                guard state.mode == .edit,
                      !state.hasHydratedEditOptions,
                      let direction = state.selectedDirection,
                      let routeId = state.mbtaRouteId else {
                    return .none
                }

                state.hasHydratedEditOptions = true
                let fetchStops = mbtaClient.fetchStops
                return .run { send in
                    do {
                        let stops = try await fetchStops(direction.directionId, routeId)
                        await send(.editOptionsHydrated(stops))
                    } catch {
                        await send(.apiFailure)
                    }
                }

            case let .transitTypeSelected(type):
                state.selectedType = type
                switch type.apiStrategy {
                case let .skipToDirection(mbtaRouteId):
                    state.mbtaRouteId = mbtaRouteId
                    state.currentFormStep = .selectDirection
                    let fetchDirections = mbtaClient.fetchDirections
                    return .run { send in
                        do {
                            let directions = try await fetchDirections(mbtaRouteId)
                            await send(.directionsLoaded(directions))
                        } catch {
                            await send(.apiFailure)
                        }
                    }

                case let .fetchRoutes(filterKey, filterValue):
                    let fetchBranches = mbtaClient.fetchBranches
                    return .run { send in
                        do {
                            let branches = try await fetchBranches(filterKey, filterValue)
                            await send(.branchesLoaded(branches))
                        } catch {
                            await send(.apiFailure)
                        }
                    }
                }

            case let .branchesLoaded(options):
                state.currentFormStep = .selectBranch
                state.branchOptions = options
                return .none

            case let .branchSelected(branch):
                state.selectedBranch = branch
                state.mbtaRouteId = branch.id

                if branch.directions.isEmpty {
                    let fetchDirections = mbtaClient.fetchDirections
                    return .run { send in
                        do {
                            let directions = try await fetchDirections(branch.id)
                            await send(.directionsLoaded(directions))
                        } catch {
                            await send(.apiFailure)
                        }
                    }
                } else {
                    return .send(.directionsLoaded(branch.directions))
                }

            case let .directionsLoaded(options):
                state.currentFormStep = .selectDirection
                state.directionOptions = options
                return .none

            case let .directionSelected(direction, mbtaRouteId):
                state.selectedDirection = direction
                let fetchStops = mbtaClient.fetchStops
                return .run { send in
                    do {
                        let stops = try await fetchStops(direction.directionId, mbtaRouteId)
                        await send(.stopsLoaded(stops))
                    } catch {
                        await send(.apiFailure)
                    }
                }

            case let .stopsLoaded(options):
                state.currentFormStep = .selectStartStop
                state.stopOptions = options
                state.hasHydratedEditOptions = true
                return .none

            case let .editOptionsHydrated(options):
                var hydratedStops = options
                if let savedStart = state.selectedStartStop {
                        if let freshStart = hydratedStops.first(where: { $0.mbtaStopId == savedStart.mbtaStopId }) {
                            state.selectedStartStop = freshStart
                        } else {
                            // Safety fallback: If API doesn't return it exactly, keep the saved one
                            hydratedStops.append(savedStart)
                            print("api did not return exact stop")
                        }
                    }

                    // 2. Re-align the End Stop to the fresh API instance
                if let savedEnd = state.selectedEndStop {
                    if let freshEnd = hydratedStops.first(where: { $0.mbtaStopId == savedEnd.mbtaStopId }) {
                        state.selectedEndStop = freshEnd
                    } else {
                        hydratedStops.append(savedEnd)
                    }
                }
                state.stopOptions = hydratedStops
                state.hasHydratedEditOptions = true
                return .send(.buildLeg)

            case let .startStopSelected(stop):
                state.selectedStartStop = stop
                state.currentFormStep = .selectEndStop
                return .none

            case let .endStopSelected(stop):
                state.selectedEndStop = stop
                return .send(.buildLeg)

            case .buildLeg:
                guard let startStop = state.selectedStartStop,
                      let endStop = state.selectedEndStop,
                      let mbtaRouteId = state.mbtaRouteId,
                      let transitType = state.selectedType,
                      let transitDirection = state.selectedDirection else {
                    return .none
                }

                state.currentLeg = Leg(
                    id: state.currentLeg?.id ?? UUID(),
                    startStop: startStop,
                    endStop: endStop,
                    mbtaRouteId: mbtaRouteId,
                    transitType: transitType,
                    transitBranch: state.selectedBranch,
                    transitDirection: transitDirection
                )
                return .none

            case .resetTypeSelection:
                reset(.type, state: &state)
                return .none

            case .resetBranchSelection:
                reset(.branch, state: &state)
                return .none

            case .resetDirectionSelection:
                reset(.direction, state: &state)
                return .none

            case .resetStartStopSelection:
                reset(.startStop, state: &state)
                return .none

            case .primaryButtonTapped:
                guard let leg = state.currentLeg else {
                    return .none
                }

                switch state.mode {
                case .create:
                    return .send(.delegate(.addAnotherLeg(leg)))
                case .edit:
                    return .none
                }

            case .saveButtonTapped:
                guard let leg = state.currentLeg else {
                    return .none
                }

                switch state.mode {
                case .create:
                    return .send(.delegate(.completeRoute(leg)))
                case .edit:
                    return .send(.delegate(.saveEditedLeg(leg)))
                }

            case .apiFailure:
                state.destination = .alert(.apiFailure())
                return .none

            case .destination, .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension LegFormFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<LegFormFeature.Action.Alert>)
    }
}

extension LegFormFeature.Destination.State: Equatable {}
extension LegFormFeature.Destination.Action: Equatable {}

extension AlertState where Action == LegFormFeature.Action.Alert {
    static func apiFailure() -> Self {
        Self {
            TextState("Something went wrong")
        }
    }
}

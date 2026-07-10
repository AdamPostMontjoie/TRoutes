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
    case addToExisting
}
enum FormStep: Equatable {
    case selectType
    case selectBranch
    case selectDirection
    case selectStartStop
    case selectEndStop
}

@Reducer
struct LegFormFeature {
    private enum ResetScope {
        case type
        case branch
        case direction
        case startStop
        case endStop
    }

    private enum CancelID: Hashable {
        case branches
        case directions
        case stops
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
            state.hasHydratedEditBranchOptions = false
            state.hasHydratedEditDirectionOptions = false
            state.hasHydratedEditStopOptions = false

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
            state.hasHydratedEditDirectionOptions = false
            state.hasHydratedEditStopOptions = false

        case .direction:
            state.selectedDirection = nil
            state.stopOptions = []
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.currentLeg = nil
            state.currentFormStep = .selectDirection
            state.hasHydratedEditStopOptions = false

        case .startStop:
            state.selectedStartStop = nil
            state.selectedEndStop = nil
            state.currentLeg = nil
            state.currentFormStep = .selectStartStop

        case .endStop:
            state.selectedEndStop = nil
            state.currentLeg = nil
            state.currentFormStep = .selectEndStop
        }
    }
    // MARK: - State
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
        var editingLegId: UUID?
        
        var hasHydratedEditBranchOptions = false
        var hasHydratedEditDirectionOptions = false
        var hasHydratedEditStopOptions = false

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
            self.editingLegId = leg.id
            self.currentFormStep = .selectEndStop

            self.selectedBranch = leg.transitBranch
            self.branchOptions = leg.transitBranch.map { [$0] }
            self.selectedDirection = leg.transitDirection
            self.directionOptions = leg.transitDirection.map { [$0] }
            self.stopOptions = [leg.startStop, leg.endStop]
        }
    }
    // MARK: - Actions
    enum Action: Equatable {
        case transitTypeSelected(TransitType)
        case branchesLoaded([TransitBranch])
        case branchSelected(TransitBranch)
        case directionsLoaded([TransitDirection])
        case directionSelected(TransitDirection, String)
        case stopsLoaded([Stop])
        case editBranchOptionsHydrated([TransitBranch])
        case editDirectionOptionsHydrated([TransitDirection])
        case editStopOptionsHydrated([Stop])
        case startStopSelected(Stop)
        case endStopSelected(Stop)

        case buildLeg

        case resetTypeSelection
        case resetBranchSelection
        case resetDirectionSelection
        case resetStartStopSelection
        case resetEndStopSelection

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
            case addLeg(Leg)
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
                guard state.mode == .edit else {
                    return .none
                }

                var effects: [Effect<Action>] = []

                if !state.hasHydratedEditBranchOptions,
                   let selectedType = state.selectedType,
                   case let .fetchRoutes(filterKey, filterValue) = selectedType.apiStrategy {
                    state.hasHydratedEditBranchOptions = true
                    let fetchBranches = mbtaClient.fetchBranches
                    effects.append(
                        .run { send in
                            do {
                                let branches = try await fetchBranches(filterKey, filterValue, .formRequest)
                                await send(.editBranchOptionsHydrated(branches))
                            } catch {
                                await send(.apiFailure)
                            }
                        }
                    )
                }

                if !state.hasHydratedEditDirectionOptions,
                   let routeId = state.mbtaRouteId {
                    state.hasHydratedEditDirectionOptions = true
                    let fetchDirections = mbtaClient.fetchDirections
                    effects.append(
                        .run { send in
                            do {
                                let directions = try await fetchDirections(routeId, .formRequest)
                                await send(.editDirectionOptionsHydrated(directions))
                            } catch {
                                await send(.apiFailure)
                            }
                        }
                    )
                }

                if !state.hasHydratedEditStopOptions,
                   let direction = state.selectedDirection,
                   let routeId = state.mbtaRouteId {
                    state.hasHydratedEditStopOptions = true
                    let fetchStops = mbtaClient.fetchStops
                    effects.append(
                        .run { send in
                            do {
                                let stops = try await fetchStops(direction.directionId, routeId, .formRequest)
                                await send(.editStopOptionsHydrated(stops))
                            } catch {
                                await send(.apiFailure)
                            }
                        }
                    )
                }

                return .merge(effects)

            case let .transitTypeSelected(type):
                state.selectedType = type
                switch type.apiStrategy {
                case let .skipToDirection(mbtaRouteId):
                    state.mbtaRouteId = mbtaRouteId
                    state.currentFormStep = .selectDirection
                    let fetchDirections = mbtaClient.fetchDirections
                    return .run { send in
                        do {
                            let directions = try await fetchDirections(mbtaRouteId, .formRequest)
                            await send(.directionsLoaded(directions))
                        } catch {
                            await send(.apiFailure)
                        }
                    }
                    .cancellable(id: CancelID.directions, cancelInFlight: true)

                case let .fetchRoutes(filterKey, filterValue):
                    let fetchBranches = mbtaClient.fetchBranches
                    return .run { send in
                        do {
                            let branches = try await fetchBranches(filterKey, filterValue, .formRequest)
                            await send(.branchesLoaded(branches))
                        } catch {
                            await send(.apiFailure)
                        }
                    }
                    .cancellable(id: CancelID.branches, cancelInFlight: true)
                }

            case let .branchesLoaded(options):
                guard state.selectedType != nil else {
                    return .none
                }

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
                            let directions = try await fetchDirections(branch.id, .formRequest)
                            await send(.directionsLoaded(directions))
                        } catch {
                            await send(.apiFailure)
                        }
                    }
                    .cancellable(id: CancelID.directions, cancelInFlight: true)
                } else {
                    return .send(.directionsLoaded(branch.directions))
                }

            case let .directionsLoaded(options):
                guard state.mbtaRouteId != nil else {
                    return .none
                }

                state.currentFormStep = .selectDirection
                state.directionOptions = options
                return .none

            case let .directionSelected(direction, mbtaRouteId):
                state.selectedDirection = direction
                let fetchStops = mbtaClient.fetchStops
                return .run { send in
                    do {
                        let stops = try await fetchStops(direction.directionId, mbtaRouteId, .formRequest)
                        await send(.stopsLoaded(stops))
                    } catch {
                        await send(.apiFailure)
                    }
                }
                .cancellable(id: CancelID.stops, cancelInFlight: true)

            case let .stopsLoaded(options):
                guard state.selectedDirection != nil,
                      state.mbtaRouteId != nil else {
                    return .none
                }

                state.currentFormStep = .selectStartStop
                state.stopOptions = options
                state.hasHydratedEditStopOptions = true
                return .none

            case let .editBranchOptionsHydrated(options):
                var hydratedBranches = options
                if let savedBranch = state.selectedBranch {
                    if let freshBranch = hydratedBranches.first(where: { $0.id == savedBranch.id }) {
                        state.selectedBranch = freshBranch
                        state.mbtaRouteId = freshBranch.id
                    } else {
                        hydratedBranches.append(savedBranch)
                    }
                }

                state.branchOptions = hydratedBranches
                state.hasHydratedEditBranchOptions = true
                return .send(.buildLeg)

            case let .editDirectionOptionsHydrated(options):
                var hydratedDirections = options
                if let savedDirection = state.selectedDirection {
                    if let freshDirection = hydratedDirections.first(where: { $0.directionId == savedDirection.directionId }) {
                        state.selectedDirection = freshDirection
                    } else {
                        hydratedDirections.append(savedDirection)
                    }
                }

                state.directionOptions = hydratedDirections
                state.hasHydratedEditDirectionOptions = true
                return .send(.buildLeg)

            case let .editStopOptionsHydrated(options):
                var hydratedStops = options
                if let savedStart = state.selectedStartStop {
                    if let freshStart = hydratedStops.first(where: { $0.mbtaStopId == savedStart.mbtaStopId }) {
                        state.selectedStartStop = freshStart
                    } else {
                        hydratedStops.append(savedStart)
                    }
                }

                if let savedEnd = state.selectedEndStop {
                    if let freshEnd = hydratedStops.first(where: { $0.mbtaStopId == savedEnd.mbtaStopId }) {
                        state.selectedEndStop = freshEnd
                    } else {
                        hydratedStops.append(savedEnd)
                    }
                }

                state.stopOptions = hydratedStops
                state.hasHydratedEditStopOptions = true
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
                    id: state.editingLegId ?? state.currentLeg?.id ?? UUID(),
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
                return .merge(
                    .cancel(id: CancelID.branches),
                    .cancel(id: CancelID.directions),
                    .cancel(id: CancelID.stops)
                )

            case .resetBranchSelection:
                reset(.branch, state: &state)
                return .merge(
                    .cancel(id: CancelID.directions),
                    .cancel(id: CancelID.stops)
                )

            case .resetDirectionSelection:
                reset(.direction, state: &state)
                return .cancel(id: CancelID.stops)

            case .resetStartStopSelection:
                reset(.startStop, state: &state)
                return .none

            case .resetEndStopSelection:
                reset(.endStop, state: &state)
                return .none

            case .primaryButtonTapped:
                guard let leg = state.currentLeg else {
                    return .none
                }

                switch state.mode {
                case .create, .addToExisting:
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
                case .addToExisting:
                    return .send(.delegate(.addLeg(leg)))
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

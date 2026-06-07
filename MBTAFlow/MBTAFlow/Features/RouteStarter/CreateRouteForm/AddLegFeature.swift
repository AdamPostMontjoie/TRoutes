//
//  AddLegFeature.swift
//  MBTAFlow
//
//  Created by Adam Post on 6/6/26.
//

import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct AddLegFeature {
    @ObservableState
    struct State: Equatable {
        var typeOptions: [TransitType] = TransitType.allCases
        var selectedType: TransitType?
        //TODO define
        var branchOptions: [TransitBranch]? // we only want to display the names but we can hold all
        var selectedBranch: TransitBranch?
        //TODO define
        var directionOptions: [TransitDirection]? //we are going to need to pass through the names
        var selectedDirection: TransitDirection?
        //TODO define
        
        //later on we should refine the stop options so the user cannot select a stop that doesn't make sense with direction
        var stopOptions: [Stop] = []
        var selectedStartStop: Stop?
        
        var selectedEndStop:Stop?
        
        var mbtaRouteId: String?
        var currentFormStep:FormStep = .selectType
        
        var currentLeg:Leg?
        
        @Presents var destination:Destination.State?
    }
    
    //the loaded features will also need to set the options, ommitting for now
    // we need to have an option to remove an entire selected stop from the stack.
    enum Action: Equatable {
        case createButtonTapped
        case transitTypeSelected(TransitType)
        case branchesLoaded([TransitBranch])
        case branchSelected(TransitBranch)
        case directionsLoaded([TransitDirection])
        case directionSelected(TransitDirection, String)
        case stopsLoaded([Stop])
        case startStopSelected(Stop)
        case endStopSelected(Stop)
        
        case buildLeg
        
        case resetTypeSelection
        case resetBranchSelection
        case resetDirectionSelection
        case resetStartStopSelection
        //we don't have a stop reset because we don't need to lock stop selection
        case addLegButtonTapped
        case saveRouteButtonTapped //triggers alert for confirmation, other action needed
        case apiFailure
        
        case destination(PresentationAction<Destination.Action>)
        enum Alert: Equatable {
            case apiFailure //alert
        }
        case delegate(Delegate)
        enum Delegate: Equatable {
            case completeRoute(Leg)
            case addAnotherLeg(Leg)
        }
        
    }
    
    @Dependency(\.mbtaClient) var mbtaClient: MBTAClient
    @Dependency(\.databaseClient) var databaseClient: DatabaseClient
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .createButtonTapped:
                return .none
            case let .transitTypeSelected(type):
                state.selectedType = type
                switch type.apiStrategy {
                    // there is only 1 path
                    case let .skipToDirection(mbtaRouteId):
                        state.mbtaRouteId = mbtaRouteId
                        state.currentFormStep = FormStep.selectDirection
                        //fetch direction
                        return .run { send in
                            do {
                                let directions = try await mbtaClient.fetchDirections(mbtaRouteId)
                                await send(.directionsLoaded(directions))
                            }
                            catch {
                                print(error)
                                await send(.apiFailure)
                            }
                        }
                        
                    case let .fetchRoutes(filterKey, filterValue):
                        // (Green Line Path)
                        // We need more info. Show a loading state and ask the dumb API client for the data.
                        return .run { send in
                            do {
                                let branches = try await mbtaClient.fetchBranches(filterKey, filterValue)
                                await send(.branchesLoaded(branches))
                            }
                            catch {
                                print(error)
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
                if state.selectedBranch?.directions == nil {
                    return .run { send in
                        do {
                            let directions = try await mbtaClient.fetchDirections(branch.id)
                            await send(.directionsLoaded(directions))
                        }
                        catch {
                            print(error)
                            await send(.apiFailure)
                        }
                    }

                } else {
                    return .send(.directionsLoaded(state.selectedBranch!.directions))
                }
            case let .directionsLoaded(options):
                state.currentFormStep = .selectDirection
                state.directionOptions = options
                return .none
            case let .directionSelected(direction, mbtaRouteId):
                state.selectedDirection = direction
                return .run { send in
                    do {
                        let stops = try await mbtaClient.fetchStops(direction.directionId, mbtaRouteId)
                        await send(.stopsLoaded(stops))
                    }
                    catch {
                        print(error)
                        await send(.apiFailure)
                    }
                }
            case let .stopsLoaded(options):
                state.currentFormStep = .selectStartStop
                state.stopOptions = options
                return .none
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
                      let transitType = state.selectedType else {
                    return .none
                }
                state.currentLeg = Leg(
                    startStop: startStop,
                    endStop: endStop,
                    mbtaRouteId: mbtaRouteId,
                    transitType: transitType
                )
                return .none
            case .resetTypeSelection:
                state.selectedType = nil
                state.selectedBranch = nil
                state.selectedDirection = nil
                state.selectedStartStop = nil
                state.selectedEndStop = nil
                state.mbtaRouteId = nil
                state.currentLeg = nil
                state.currentFormStep = .selectType
                
                return .none
            case .resetBranchSelection:
                state.selectedBranch = nil
                state.selectedDirection = nil
                state.selectedStartStop = nil
                state.selectedEndStop = nil
                state.mbtaRouteId = nil
                state.currentLeg = nil
                state.currentFormStep = .selectBranch
                return .none
            case .resetDirectionSelection:
                state.selectedDirection = nil
                state.selectedStartStop = nil
                state.selectedEndStop = nil
                state.mbtaRouteId = nil
                state.currentLeg = nil
                state.currentFormStep = .selectDirection
                return .none
            case .resetStartStopSelection:
                state.selectedStartStop = nil
                state.selectedEndStop = nil
                state.currentLeg = nil
                state.currentFormStep = .selectStartStop
                return .none
            case .addLegButtonTapped:
                //hands the leg to the parent, they will wipe state
                //we don't need to here (I think) we will include a back option if not first leg
                guard let leg = state.currentLeg else {
                    return .none
                }
                return .send(.delegate(.addAnotherLeg(leg)))
            case .saveRouteButtonTapped:
                //triggers alert for save confirmation
                
                //if the user decides to keep adding more, we will set the isLastStop to be false again
                guard let leg = state.currentLeg else {
                    return .none
                }
                return .send(.delegate(.completeRoute(leg)))
            case .apiFailure:
                state.destination = .alert(.apiFailure())
                return .none
            case .destination:
                return .none
            case .delegate:
                return .none
            }
        }
        ._printChanges()
        .ifLet(\.$destination, action: \.destination)
    }
}


extension AddLegFeature {
    @Reducer
    enum Destination {
        case alert(AlertState<AddLegFeature.Action.Alert>)
    }
}

extension AddLegFeature.Destination.State: Equatable {}
extension AddLegFeature.Destination.Action: Equatable {}

enum FormStep: Equatable {
    case selectType
    case selectBranch
    case selectDirection
    case selectStartStop
    case selectEndStop
}

extension AlertState where Action == AddLegFeature.Action.Alert {
    static func apiFailure() -> Self {
        Self {
            TextState("Something went wrong")
        }
    }
}

//
//  UndergroundManager.swift
//  TRoutes
//
//  Created by Adam Post on 6/27/26.
//
import CoreLocation
import Dependencies



@MainActor
final class UndergroundManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = UndergroundManager()

    private let locationManager = CLLocationManager()

    private enum VehicleTrackingPhase {
        case idle
        case waitingToBoard
        case trackingVehicle
        case completed
    }

    private var currentVehicleId:String? //we need to track what train/bus we are supposed to be monitoring
    private var currentVehicleTrip:String?
    private var currentVehicleStopSequence:Int?
    private var currentVehicleRouteId:String?
    private var currentLeg:Leg? //refine/specify later
    private var currentMatchResult: TransitTripMatchResult?
    private var phase: VehicleTrackingPhase = .idle
    private var preparedCommand: JourneyCommand? 
    
    private var apiTimer:Timer?
    
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.databaseClient) var databaseClient: DatabaseClient


    func startSession() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .otherNavigation
        locationManager.startUpdatingLocation()

        guard currentVehicleId != nil else { return }
        Task { await fetchVehicleData() }
    }
    
    //journey engine hands us a vehicle to track
    //only should be done when we're at stop
    func updateTrackedVehicle(prediction: TransitPrediction, leg: Leg?) async {
        currentVehicleId = prediction.vehicleId
        currentVehicleTrip = prediction.tripId
        currentVehicleStopSequence = prediction.stopSequence
        currentLeg = leg
        currentVehicleRouteId = leg?.mbtaRouteId
        currentMatchResult = nil
        preparedCommand = nil
        phase = .waitingToBoard
        await fetchVehicleData()
    }

    func stopSession() {
        locationManager.stopUpdatingLocation()
        cancelTimer()
        resetTracking()
    }
    
    //polls api for where the current vehicle is.
    //we will initially assume user always takes first available vehicle/vehicle of next time
    //this will not be accurate, so need to use incoming location data to determine
    private func fetchVehicleData() async {
        guard let vehicleId = currentVehicleId else { return }
        do {
            let vehicleData = try await mbtaClient.fetchVehicleData(vehicleId)
            guard currentVehicleId == vehicleId else {
                print("Ignoring stale underground vehicle response for \(vehicleId)")
                return
            }
            await handleVehicleData(vehicleData: vehicleData)
        }
        catch {
            print("error fetching vehicle data: \(error)")
            handleVehicleFetchError(error: error)
        }
    }
    
    //this will be used to display an ETA when we're in movement by polling the next stop, and to figure out dynamic timer setting (?). May do for region manager later
    //stop events endpoint looks good for this
    private func fetchVehicleArrivalEstimation() async {
        
    }
    
    //what does this mean? where are we? should we set timer?
    //break actual actions into sub funcs
    private func handleVehicleData(vehicleData:VehicleData) async {
        updateTrackingSnapshot(with: vehicleData)

        switch phase {
        case .idle, .completed:
            return

        case .waitingToBoard:
            await matchTrainPattern(vehicleData: vehicleData)

        case .trackingVehicle:
            evaluateTrackedVehicleProgress(vehicleData: vehicleData)
        }

        if phase != .completed {
            setTimer(time: 15)
        }        
    }
    
    private func matchTrainPattern(vehicleData:VehicleData) async {
        do {
            guard let matchResult = try await databaseClient.matchTripID(
                currentLeg?.mbtaRouteId ?? vehicleData.routeId,
                currentLeg?.transitDirection?.directionId ?? vehicleData.directionId,
                vehicleData.stopId,
                vehicleData.currentStopSequence ?? currentVehicleStopSequence,
                vehicleData.currentStatus,
                currentLeg?.startStop.mbtaStopId,
                currentLeg?.endStop.mbtaStopId
            ) else {
                print("UndergroundManager could not match a usable stop sequence yet")
                return
            }

            currentMatchResult = matchResult
            evaluateBoardingProgress(vehicleData: vehicleData, matchResult: matchResult)
        }
        catch {
            handleVehicleFetchError(error: error)
        }
    }

    private func updateTrackingSnapshot(with vehicleData: VehicleData) {
        currentVehicleRouteId = vehicleData.routeId ?? currentVehicleRouteId
        currentVehicleTrip = vehicleData.tripId ?? currentVehicleTrip
        currentVehicleStopSequence = vehicleData.currentStopSequence ?? currentVehicleStopSequence
    }

    private func evaluateBoardingProgress(vehicleData: VehicleData, matchResult: TransitTripMatchResult) {
        guard hasVehicleLeftOrigin(vehicleData: vehicleData, matchResult: matchResult),
              let originStopId = currentLeg?.startStop.mbtaStopId else {
            return
        }

        phase = .trackingVehicle
        prepareCommand(.executeExit(stopId: originStopId))
        evaluateTrackedVehicleProgress(vehicleData: vehicleData)
    }

    private func evaluateTrackedVehicleProgress(vehicleData: VehicleData) {
        guard let matchResult = currentMatchResult,
              let currentVehicleSequence = vehicleData.currentStopSequence ?? currentVehicleStopSequence,
              let destinationStopId = currentLeg?.endStop.mbtaStopId else {
            return
        }

        if currentVehicleSequence >= matchResult.destinationSequence {
            phase = .completed
            cancelTimer()
            prepareCommand(.executeEntry(stopId: destinationStopId))
        }
    }

    private func hasVehicleLeftOrigin(vehicleData: VehicleData, matchResult: TransitTripMatchResult) -> Bool {
        guard let currentVehicleSequence = vehicleData.currentStopSequence ?? currentVehicleStopSequence else {
            return false
        }

        if currentVehicleSequence > matchResult.originSequence {
            return true
        }

        guard currentVehicleSequence == matchResult.originSequence,
              let currentVehicleStatus = vehicleData.currentStatus?.lowercased() else {
            return false
        }

        return currentVehicleStatus == "in_transit_to"
    }

    private func prepareCommand(_ command: JourneyCommand) {
        guard preparedCommand != command else { return }
        preparedCommand = command
        print("UndergroundManager prepared future command: \(command)")
    }
    
    //if we can't get any info, that will be an error
    //specific enum will be defined, this is different than a prediction error
    private func handleVehicleFetchError(error: Error){
        print("this is where we could deal with internet issues, like timeout errors or api issues")
    }
    
    //dynamic, and it ending means it's time to fetch vehicle info again.
    private func setTimer(time: TimeInterval) {
        cancelTimer()
        
        apiTimer = Timer.scheduledTimer(withTimeInterval: time, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("timer went off")
                await self?.fetchVehicleData()
            }
        }
    }
    
    private func cancelTimer() {
        apiTimer?.invalidate()
        apiTimer = nil
    }

    private func resetTracking() {
        currentVehicleId = nil
        currentVehicleTrip = nil
        currentVehicleStopSequence = nil
        currentVehicleRouteId = nil
        currentLeg = nil
        currentMatchResult = nil
        preparedCommand = nil
        phase = .idle
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //continuation?.yield(.locationUpdate(locations))
    }
    //used to handle pause, which ios will do if location doesn't change for enough time
    //we can possibly use the countdown timer to determine when we want to restart updates
    //apparently immediately restarting with reduced accuracy also an option
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager){
        
    }
    
    //ios tells app updates have been resumed
    //handle behavior here
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        
    }
    
    //ios tells app it was unable to receive a location
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error
    ){
        
    }

//    func makeEventStream() -> AsyncStream<UndergroundEvent> {
//        AsyncStream { continuation in
//            self.continuation = continuation
//            
//            continuation.onTermination = { _ in
//                print("underground event stream termination")
//            }
//        }
//    }
}

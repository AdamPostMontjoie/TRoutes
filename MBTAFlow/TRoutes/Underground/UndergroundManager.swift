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
    
    private struct TrackedVehicleState {
        var currentVehicleId: String?
        var currentVehicleTrip: String?
        var currentVehicleStopSequence: Int?
        var currentVehicleRouteId: String?
        var currentVehicleStatus: String?

        mutating func updateVehicleInfo(
            vehicleId: String? = nil,
            tripId: String? = nil,
            stopSequence: Int? = nil,
            routeId: String? = nil,
            status: String? = nil
        ) {
            self.currentVehicleId = vehicleId
            self.currentVehicleTrip = tripId
            self.currentVehicleStopSequence = stopSequence
            self.currentVehicleRouteId = routeId
            self.currentVehicleStatus = status
        }
    }
    
    private var currentVehicle = TrackedVehicleState()
    private var currentLeg: ResolvedLeg? //refine to resolved leg
    //private var currentMatchResult: TransitTripMatchResult?
    private var phase: VehicleTrackingPhase = .idle
    private var preparedCommand: JourneyCommand? 
    
    private var apiTimer: Timer?
    
    @Dependency(\.mbtaClient) var mbtaClient
    //@Dependency(\.databaseClient) var databaseClient: DatabaseClient


    func startSession() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .otherNavigation
        locationManager.startUpdatingLocation()

        guard currentVehicle.currentVehicleId != nil else { return }
        Task { await fetchVehicleData() }
    }
    
    //journey engine hands us a vehicle to track
    //only should be done when we're at stop
    func updateTrackedVehicle(prediction: TransitPrediction, leg: ResolvedLeg) async {
        currentVehicle.updateVehicleInfo(
            vehicleId: prediction.vehicleId,
            tripId: prediction.tripId,
            stopSequence: prediction.stopSequence,
            routeId: leg.mbtaRouteId
        )
        currentLeg = leg
        //currentMatchResult = nil
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
        guard let vehicleId = currentVehicle.currentVehicleId else { return }
        do {
            let vehicleData = try await mbtaClient.fetchVehicleData(vehicleId)
            guard currentVehicle.currentVehicleId == vehicleId else {
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

    private func handleVehicleData(vehicleData:VehicleData) async {
        updateTrackingSnapshot(with: vehicleData)

        switch phase {
        case .idle, .completed:
            return

        case .waitingToBoard:
            //await matchVehiclePattern(vehicleData: vehicleData)
            print("UndergroundManager vehicle matching is paused until resolved-leg live trip mapping is wired.")

        case .trackingVehicle:
            //evaluateTrackedVehicleProgress(vehicleData: vehicleData)
            print("UndergroundManager vehicle progress evaluation is paused until resolved-leg live trip mapping is wired.")
        }

        if phase != .completed {
            setTimer(time: 15)
        }        
    }

    private func updateTrackingSnapshot(with vehicleData: VehicleData) {
        currentVehicle.updateVehicleInfo(
            vehicleId: currentVehicle.currentVehicleId,
            tripId: vehicleData.tripId ?? currentVehicle.currentVehicleTrip,
            stopSequence: vehicleData.currentStopSequence ?? currentVehicle.currentVehicleStopSequence,
            routeId: vehicleData.routeId ?? currentVehicle.currentVehicleRouteId,
            status: vehicleData.currentStatus ?? currentVehicle.currentVehicleStatus
        )
    }

    private func evaluateBoardingProgress(vehicleData: VehicleData) {
        guard hasVehicleLeftOrigin(vehicleData: vehicleData),
              let originStopId = currentLeg?.startStop.mbtaStopId else {
            return
        }

        phase = .trackingVehicle
        prepareCommand(.executeExit(stopId: originStopId))
        evaluateTrackedVehicleProgress(vehicleData: vehicleData)
    }

    private func evaluateTrackedVehicleProgress(vehicleData: VehicleData) {
        guard let currentVehicleSequence = vehicleData.currentStopSequence ?? currentVehicle.currentVehicleStopSequence,
              let destinationStopId = currentLeg?.endStop.mbtaStopId else {
            return
        }

        if currentVehicleSequence >= currentLeg position lol{
            phase = .completed
            cancelTimer()
            prepareCommand(.executeEntry(stopId: destinationStopId))
        }
    }

    private func hasVehicleLeftOrigin(vehicleData: VehicleData) -> Bool {
        guard let currentVehicleSequence = vehicleData.currentStopSequence ?? currentVehicle.currentVehicleStopSequence else {
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
        currentVehicle = TrackedVehicleState()
        currentLeg = nil
        //currentMatchResult = nil
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

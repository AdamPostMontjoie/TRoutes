//
//  UndergroundManager.swift
//  TRoutes
//
//  Created by Adam Post on 6/27/26.
//
import CoreLocation
import Dependencies
import Foundation



@MainActor
final class UndergroundManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = UndergroundManager()

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    private enum VehicleTrackingPhase {
        case idle
        case waitingToBoard
        case trackingVehicle
    }
    
    private struct TrackedVehicleState {
        var currentVehicleId: String?
        var currentVehicleTrip: String?
        var currentVehicleStopId: String?
        var currentVehicleAPIStopSequence: Int?
        var currentVehicleRouteId: String?
        var currentVehicleStatus: String?

        mutating func updateVehicleInfo(
            vehicleId: String? = nil,
            tripId: String? = nil,
            stopId: String? = nil
        ) {
            self.currentVehicleId = vehicleId
            self.currentVehicleTrip = tripId
            self.currentVehicleStopId = stopId
        }
    }

    private struct TrackedVehiclePosition {
        let vehicleStopId: String?
        let apiStopSequence: Int?
        let vehicleStatus: String?
        init(
            vehicleStopId: String?,
            apiStopSequence: Int?,
            vehicleStatus: String?
        ) {
            self.vehicleStopId = vehicleStopId
            self.apiStopSequence = apiStopSequence
            self.vehicleStatus = vehicleStatus
        }
    }
    
    private var currentVehicle = TrackedVehicleState()
    private var currentStopToMonitorId: String?
    private var previousVehiclePosition: TrackedVehiclePosition?
    private var currentVehiclePosition: TrackedVehiclePosition?
    private var phase: VehicleTrackingPhase = .idle
    
    // GPS proximity detection for first underground boarding stop
    private var boardingStopCoordinate: CLLocationCoordinate2D?
    private var isFirstStop = false
    private var hasYieldedInitialEntry = false
    
    private var preparedCommand: JourneyCommand?
    private var continuation: AsyncStream<JourneyCommand>.Continuation?
    
    private var apiTimer: Timer?
    
    @Dependency(\.mbtaClient) var mbtaClient
    
    func makeEventStream() -> AsyncStream<JourneyCommand> {
        AsyncStream { continuation in
            print("UGM event stream created")
            self.continuation = continuation

            continuation.onTermination = { _ in
                print("underground event stream termination")
            }
        }
    }

    func startSession() {
        print("UGM startSession")
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .otherNavigation
        locationManager.startUpdatingLocation()

        guard currentVehicle.currentVehicleId != nil else {
            print("UGM startSession no vehicle")
            return
        }
        Task { await fetchVehicleData() }
    }
    
    //journey engine hands us a vehicle to start tracking
    func setTrackedVehicle(
        vehicleId: String,
        tripId: String,
        boardingStopId: String,
        waitToBoard: Bool,
        stopLatitude: Double,
        stopLongitude: Double,
        isFirstStop: Bool
    ) async {
        currentVehicle = TrackedVehicleState()
        currentVehicle.updateVehicleInfo(
            vehicleId: vehicleId,
            tripId: tripId
        )
        currentStopToMonitorId = boardingStopId
        previousVehiclePosition = nil
        currentVehiclePosition = nil
        preparedCommand = nil
        phase = waitToBoard ? .waitingToBoard: .trackingVehicle
        
        boardingStopCoordinate = CLLocationCoordinate2D(
            latitude: stopLatitude, longitude: stopLongitude
        )
        self.isFirstStop = isFirstStop
        hasYieldedInitialEntry = false
        
        print("UGM setTrackedVehicle vehicle: \(vehicleId) trip: \(tripId) stop: \(boardingStopId) waitToBoard: \(waitToBoard) isFirstStop: \(isFirstStop)")

        await fetchVehicleData()
    }


    func stopFunction() {
        locationManager.stopUpdatingLocation()
        cancelTimer()
        resetTracking()
    }
    
    func killManager(){
        locationManager.stopUpdatingLocation()
        cancelTimer()
        resetTracking()
        continuation?.finish()
        continuation = nil
    }
    
    //polls api for where the current vehicle is.
    //we will initially assume user always takes first available vehicle/vehicle of next time
    //this will not be accurate, so need to use incoming location data to determine
    private func fetchVehicleData() async {
        guard let vehicleId = currentVehicle.currentVehicleId else {
            print("UGM fetchVehicleData no vehicle")
            return
        }
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
        updateVehicleData(with: vehicleData)
        if phase == .idle {
            print("UGM handleVehicleData idle")
            return
        }
        updateVehiclePosition(with: vehicleData)
        printCurrentVehiclePosition()

        if phase == .waitingToBoard {
            print("UGM path waitingToBoard")
            evaluateBoardingProgress()
        }
        else if phase == .trackingVehicle {
            print("UGM path trackingVehicle")
            evaluateTrackedVehicleProgress()
        }

        if phase != .idle {
            // Refresh predictions on each poll tick
            if let stopId = currentStopToMonitorId {
                continuation?.yield(.refreshTimes(stopId: stopId))
            }
            setTimer(time: 15)
        }        
    }

    private func updateVehicleData(with vehicleData: VehicleData) {
        currentVehicle.updateVehicleInfo(
            vehicleId: currentVehicle.currentVehicleId,
            tripId: vehicleData.tripId ?? currentVehicle.currentVehicleTrip,
            stopId: vehicleData.stopId ?? currentVehicle.currentVehicleStopId
        )
        currentVehicle.currentVehicleAPIStopSequence = vehicleData.currentStopSequence ?? currentVehicle.currentVehicleAPIStopSequence
        currentVehicle.currentVehicleStatus = vehicleData.currentStatus ?? currentVehicle.currentVehicleStatus
    }


    private func updateVehiclePosition(with vehicleData: VehicleData) {

        let vehicleStopId = vehicleData.stopId ?? currentVehicle.currentVehicleStopId
        let apiStopSequence = vehicleData.currentStopSequence ?? currentVehicle.currentVehicleAPIStopSequence
        let vehicleStatus = (vehicleData.currentStatus ?? currentVehicle.currentVehicleStatus)?.lowercased()
        previousVehiclePosition = currentVehiclePosition
        currentVehiclePosition = TrackedVehiclePosition(
            vehicleStopId: vehicleStopId,
            apiStopSequence: apiStopSequence,
            vehicleStatus: vehicleStatus
        )
    }

    private func evaluateBoardingProgress() {
        let hasDepartedStop = vehicleHasDepartedStop()
        print("UGM boarding departed: \(hasDepartedStop)")
        guard hasDepartedStop else {
            return
        }

        phase = .trackingVehicle
        if let currentStopToMonitorId {
            print("UGM yield exit \(currentStopToMonitorId)")
            continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
        }
    }

    private func evaluateTrackedVehicleProgress() {
        let hasEnteredStop = vehicleHasEnteredStop()
        let hasDepartedStop = vehicleHasDepartedStop()
        print("UGM tracking entered: \(hasEnteredStop) departed: \(hasDepartedStop)")
        if hasEnteredStop,
           let currentStopToMonitorId {
            print("UGM yield entry \(currentStopToMonitorId)")
            continuation?.yield(.executeEntry(stopId: currentStopToMonitorId))
        } else if hasDepartedStop,
                  let currentStopToMonitorId {
            print("UGM yield exit \(currentStopToMonitorId)")
            continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
        }
    }

    private func vehicleHasDepartedStop() -> Bool {
        guard let currentStopToMonitorId,
              let previousVehiclePosition,
              let currentVehiclePosition else { return false }

        let wasStoppedAtTrackedStop = previousVehiclePosition.vehicleStopId == currentStopToMonitorId &&
            previousVehiclePosition.vehicleStatus == "stopped_at"
        let isStillStoppedAtTrackedStop = currentVehiclePosition.vehicleStopId == currentStopToMonitorId &&
            currentVehiclePosition.vehicleStatus == "stopped_at"

        return wasStoppedAtTrackedStop && !isStillStoppedAtTrackedStop
    }

    //check if we've entered the tracked stop.
    private func vehicleHasEnteredStop() -> Bool {
        guard let currentStopToMonitorId,
              let currentVehiclePosition else { return false }

        let isStoppedAtTrackedStop = currentVehiclePosition.vehicleStopId == currentStopToMonitorId &&
            currentVehiclePosition.vehicleStatus == "stopped_at"
        let wasAlreadyStoppedAtTrackedStop = previousVehiclePosition?.vehicleStopId == currentStopToMonitorId &&
            previousVehiclePosition?.vehicleStatus == "stopped_at"

        return isStoppedAtTrackedStop && !wasAlreadyStoppedAtTrackedStop
    }

    private func printCurrentVehiclePosition() {
        let previousStop = previousVehiclePosition?.vehicleStopId ?? "nil"
        let previousStatus = previousVehiclePosition?.vehicleStatus ?? "nil"
        let currentStop = currentVehiclePosition?.vehicleStopId ?? "nil"
        let currentStatus = currentVehiclePosition?.vehicleStatus ?? "nil"
        let currentSequence = currentVehiclePosition?.apiStopSequence.map(String.init) ?? "nil"
        let watchedStop = currentStopToMonitorId ?? "nil"
        print("UGM position watch: \(watchedStop) previous: \(previousStop) \(previousStatus) current: \(currentStop) \(currentStatus) seq: \(currentSequence)")
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
        currentStopToMonitorId = nil
        previousVehiclePosition = nil
        currentVehiclePosition = nil
        preparedCommand = nil
        phase = .idle
        boardingStopCoordinate = nil
        isFirstStop = false
        hasYieldedInitialEntry = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .waitingToBoard,
              isFirstStop,
              !hasYieldedInitialEntry,
              let boardingCoord = boardingStopCoordinate,
              let userLocation = locations.last else { return }
        
        let stopLocation = CLLocation(
            latitude: boardingCoord.latitude,
            longitude: boardingCoord.longitude
        )
        let distance = userLocation.distance(from: stopLocation)
        print("UGM proximity check: \(distance)m from boarding stop")
        
        if distance < 150 {
            hasYieldedInitialEntry = true
            if let stopId = currentStopToMonitorId {
                print("UGM proximity entry for first stop \(stopId)")
                continuation?.yield(.executeEntry(stopId: stopId))
            }
        }
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


}

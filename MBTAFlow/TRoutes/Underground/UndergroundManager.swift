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
        case evaluatingDeparture
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
        let vehicleLatitude: Double?
        let vehicleLongitude: Double?
        init(
            vehicleStopId: String?,
            apiStopSequence: Int?,
            vehicleStatus: String?,
            vehicleLatitude: Double? = nil,
            vehicleLongitude: Double? = nil
        ) {
            self.vehicleStopId = vehicleStopId
            self.apiStopSequence = apiStopSequence
            self.vehicleStatus = vehicleStatus
            self.vehicleLatitude = vehicleLatitude
            self.vehicleLongitude = vehicleLongitude
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
    
    // Evaluating departure state
    private var evaluatingDepartureStartTime: Date?
    private static let departureEvaluationTimeout: TimeInterval = 45
    private static let boardedProximityThreshold: CLLocationDistance = 75
    private static let boardedStationDistanceThreshold: CLLocationDistance = 100
    private static let missedDistanceThreshold: CLLocationDistance = 200
    
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
        evaluatingDepartureStartTime = nil
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
        else if phase == .evaluatingDeparture {
            print("UGM path evaluatingDeparture")
            evaluateDepartureProximity()
        }

        if phase != .idle {
            // Refresh predictions on each poll tick
            if let stopId = currentStopToMonitorId {
                continuation?.yield(.refreshTimes(stopId: stopId))
            }
            // Poll faster during departure evaluation for quicker resolution
            let pollInterval: TimeInterval = phase == .evaluatingDeparture ? 10 : 15
            setTimer(time: pollInterval)
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
            vehicleStatus: vehicleStatus,
            vehicleLatitude: vehicleData.latitude,
            vehicleLongitude: vehicleData.longitude
        )
    }

    private func evaluateBoardingProgress() {
        let hasDepartedStop = vehicleHasDepartedStop()
        print("UGM boarding departed: \(hasDepartedStop)")
        guard hasDepartedStop else {
            return
        }

        // Instead of immediately yielding exit, enter the evaluating phase
        phase = .evaluatingDeparture
        evaluatingDepartureStartTime = Date()
        print("UGM entering evaluatingDeparture phase")
        evaluateDepartureProximity()
    }
    
    private func evaluateDepartureProximity() {
        guard phase == .evaluatingDeparture,
              let currentStopToMonitorId else { return }
        
        let userLocation = locationManager.location
        let vehicleLat = currentVehiclePosition?.vehicleLatitude
        let vehicleLon = currentVehiclePosition?.vehicleLongitude
        
        // Calculate user-to-vehicle distance if we have both positions
        if let userLocation,
           let vehicleLat,
           let vehicleLon {
            let vehicleLocation = CLLocation(latitude: vehicleLat, longitude: vehicleLon)
            let distanceToVehicle = userLocation.distance(from: vehicleLocation)
            let locationAge = abs(userLocation.timestamp.timeIntervalSinceNow)
            let boardingLocation = boardingStopCoordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
            let userDistanceFromBoardingStop = boardingLocation.map {
                userLocation.distance(from: $0)
            }
            let vehicleDistanceFromBoardingStop = boardingLocation.map {
                vehicleLocation.distance(from: $0)
            }
            
            print("UGM departure eval: user-to-vehicle distance: \(Int(distanceToVehicle))m, user-from-stop: \(userDistanceFromBoardingStop.map { "\(Int($0))m" } ?? "nil"), vehicle-from-stop: \(vehicleDistanceFromBoardingStop.map { "\(Int($0))m" } ?? "nil"), location age: \(Int(locationAge))s, accuracy: \(Int(userLocation.horizontalAccuracy))m")
            
            // Only trust recent GPS fixes (< 30s old) with reasonable accuracy
            if locationAge < 30 && userLocation.horizontalAccuracy < 100 {
                // Condition A: User has moved away from the boarding stop.
                if let userDistanceFromBoardingStop,
                   userDistanceFromBoardingStop > Self.boardedStationDistanceThreshold {
                    print("UGM departure resolved: BOARDED (user \(Int(userDistanceFromBoardingStop))m from stop)")
                    phase = .trackingVehicle
                    evaluatingDepartureStartTime = nil
                    continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
                    return
                }
                
                // Condition A: User remains close to the vehicle after it has actually left the stop.
                if distanceToVehicle < Self.boardedProximityThreshold,
                   let vehicleDistanceFromBoardingStop,
                   vehicleDistanceFromBoardingStop > Self.boardedStationDistanceThreshold {
                    print("UGM departure resolved: BOARDED (\(Int(distanceToVehicle))m from vehicle)")
                    phase = .trackingVehicle
                    evaluatingDepartureStartTime = nil
                    continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
                    return
                }
                
                // Condition B: Vehicle is far away from user (missed)
                if distanceToVehicle > Self.missedDistanceThreshold {
                    print("UGM departure resolved: MISSED (\(Int(distanceToVehicle))m from vehicle)")
                    phase = .idle
                    evaluatingDepartureStartTime = nil
                    continuation?.yield(.missedVehicle(stopId: currentStopToMonitorId))
                    return
                }
                
                // In between thresholds — wait for next poll
                print("UGM departure eval: inconclusive (\(Int(distanceToVehicle))m), waiting for next poll")
            }
        }
        
        // GPS is stale, unavailable, or inconclusive — ask the user after a short wait.
        if let startTime = evaluatingDepartureStartTime,
           Date().timeIntervalSince(startTime) > Self.departureEvaluationTimeout {
            print("UGM departure eval: timed out, requesting user confirmation")
            phase = .idle
            evaluatingDepartureStartTime = nil
            continuation?.yield(.confirmDeparture(stopId: currentStopToMonitorId))
            return
        }
        
        print("UGM departure eval: GPS unavailable/stale, waiting...")
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
        evaluatingDepartureStartTime = nil
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

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

    // MARK: - Types & Properties
    
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
    
    // Tunnel-entry: surface stop monitored as underground because next stop is underground.
    // GPS is guaranteed to degrade when the vehicle departs, so skip departure evaluation.
    private var isTunnelEntry = false
    
    // Evaluating departure state
    private var evaluatingDepartureStartTime: Date?
    private var highConfidenceMissedCount: Int = 0

    private static let departureEvaluationTimeout: TimeInterval = 20
    private static let boardedProximityThreshold: CLLocationDistance = 150
    private static let boardedStationDistanceThreshold: CLLocationDistance = 200
    private static let missedDistanceThreshold: CLLocationDistance = 200 //TODO: update
    
    private var preparedCommand: JourneyCommand?
    private var continuation: AsyncStream<JourneyCommand>.Continuation?
    
    private var apiTimer: Timer?
    
    @Dependency(\.mbtaClient) var mbtaClient
    
    // MARK: - Lifecycle & Stream
    
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
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 50 // Low polling initially
        locationManager.startUpdatingLocation()
    }
    
    //journey engine hands us a vehicle to start tracking
    func setTrackedVehicle(
        vehicleId: String,
        tripId: String,
        boardingStopId: String,
        waitToBoard: Bool,
        stopLatitude: Double,
        stopLongitude: Double,
        isFirstStop: Bool,
        isTunnelEntry: Bool = false
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
        highConfidenceMissedCount = 0
        phase = waitToBoard ? .waitingToBoard: .trackingVehicle
        
        boardingStopCoordinate = CLLocationCoordinate2D(
            latitude: stopLatitude, longitude: stopLongitude
        )
        self.isFirstStop = isFirstStop
        self.isTunnelEntry = isTunnelEntry
        hasYieldedInitialEntry = false
        
        print("UGM setTrackedVehicle vehicle: \(vehicleId) trip: \(tripId) stop: \(boardingStopId) waitToBoard: \(waitToBoard) isFirstStop: \(isFirstStop) tunnelEntry: \(isTunnelEntry)")

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
    
    // MARK: - API Polling
    
    //polls api for where the current vehicle is.
    //we will initially assume user always takes first available vehicle/vehicle of next time
    //this will not be accurate, so need to use incoming location data to determine
    private func fetchVehicleData() async {
        guard let vehicleId = currentVehicle.currentVehicleId else {
            print("UGM fetchVehicleData no vehicle")
            return
        }
        do {
            let vehicleData = try await mbtaClient.fetchVehicleData(vehicleId, .vehiclePosition)
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
            let pollInterval: TimeInterval = phase == .evaluatingDeparture ? 9 : 15
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

    // MARK: - State Machine Evaluation
    
    private func evaluateBoardingProgress() {
        let hasDepartedStop = vehicleHasDepartedStop()
        print("UGM boarding departed: \(hasDepartedStop)")
        guard hasDepartedStop else {
            return
        }

        // At tunnel-entry stops, GPS will be unreliable as the train enters the tunnel.
        // Skip departure evaluation and assume boarded.
        // Will be improved with CoreMotion jolt later, which will bypass any conditions if it determines we are accelerating in a vehicle
        if isTunnelEntry {
            print("UGM tunnel-entry: assuming boarded")
            phase = .trackingVehicle
            if let currentStopToMonitorId {
                continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
            }
            return
        }

        phase = .evaluatingDeparture
        locationManager.distanceFilter = kCLDistanceFilterNone // High frequency for the 30s evaluation window
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
            
            // FRESHNESS & ACCURACY FILTER (Mass Ave plunge fix)
            if locationAge < 15 && userLocation.horizontalAccuracy <= 50 {
                
                // Condition A: User remains close to the vehicle after it has actually left the stop.
                if distanceToVehicle < Self.boardedProximityThreshold,
                   let vehicleDistanceFromBoardingStop,
                   vehicleDistanceFromBoardingStop > Self.boardedStationDistanceThreshold {
                    print("UGM departure resolved: BOARDED (\(Int(distanceToVehicle))m from vehicle)")
                    phase = .trackingVehicle
                    locationManager.distanceFilter = 50 // Return to low battery polling
                    evaluatingDepartureStartTime = nil
                    highConfidenceMissedCount = 0
                    continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
                    return
                }
                
                // Condition B: User has moved away from the boarding stop (e.g. they took a bus instead).
                if let userDistanceFromBoardingStop,
                   userDistanceFromBoardingStop > Self.boardedStationDistanceThreshold {
                    print("UGM departure resolved: BOARDED (user \(Int(userDistanceFromBoardingStop))m from stop)")
                    phase = .trackingVehicle
                    locationManager.distanceFilter = 50 // Return to low battery polling
                    evaluatingDepartureStartTime = nil
                    highConfidenceMissedCount = 0
                    continuation?.yield(.executeExit(stopId: currentStopToMonitorId))
                    return
                }
                
                // Condition C: Vehicle is far away from user, user is still at station (Missed)
                if distanceToVehicle > Self.missedDistanceThreshold {
                    highConfidenceMissedCount += 1
                    print("UGM departure eval: High confidence missed. Count: \(highConfidenceMissedCount)")
                    if highConfidenceMissedCount >= 2 {
                        print("UGM departure resolved: MISSED (\(Int(distanceToVehicle))m from vehicle)")
                        phase = .idle
                        locationManager.distanceFilter = 50 // Return to low battery polling
                        evaluatingDepartureStartTime = nil
                        highConfidenceMissedCount = 0
                        continuation?.yield(.missedVehicle(stopId: currentStopToMonitorId))
                        return
                    }
                } else {
                    highConfidenceMissedCount = 0
                }
                
                // In between thresholds — wait for next poll
                print("UGM departure eval: inconclusive (\(Int(distanceToVehicle))m), waiting for next poll")
            } else {
                print("UGM departure eval: location discarded (age: \(Int(locationAge))s, accuracy: \(Int(userLocation.horizontalAccuracy))m)")
            }
        }
        
        // Timer expiration: The "Unsure" fallback
        if let startTime = evaluatingDepartureStartTime,
           Date().timeIntervalSince(startTime) > Self.departureEvaluationTimeout {
            print("UGM departure eval: 20s timeout, requesting user confirmation")
            phase = .idle
            locationManager.distanceFilter = 50 // Return to low battery polling
            evaluatingDepartureStartTime = nil
            highConfidenceMissedCount = 0
            continuation?.yield(.confirmDeparture(stopId: currentStopToMonitorId))
            return
        }
        
        print("UGM departure eval: continuing to wait...")
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

    // MARK: - State Helpers
    
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
        print("UGM User at: \(watchedStop) Vehicle was at: \(previousStop) \(previousStatus) Vehicle is at: \(currentStop) \(currentStatus) seq: \(currentSequence)")
    }


    //if we can't get any info, that will be an error
    //specific enum will be defined, this is different than a prediction error
    private func handleVehicleFetchError(error: Error){
        print("this is where we could deal with internet issues, like timeout errors or api issues")
    }
    
    // MARK: - Timers & Tracking Reset
    
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
        isTunnelEntry = false
        hasYieldedInitialEntry = false
        evaluatingDepartureStartTime = nil
        highConfidenceMissedCount = 0
    }

    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            print("UGM: Polling location [\(location.coordinate.latitude), \(location.coordinate.longitude)]")
        }
        guard phase == .waitingToBoard,
              !hasYieldedInitialEntry,
              let boardingCoord = boardingStopCoordinate,
              let userLocation = locations.last else { return }
        
        let stopLocation = CLLocation(
            latitude: boardingCoord.latitude,
            longitude: boardingCoord.longitude
        )
        let distance = userLocation.distance(from: stopLocation)
        print("UGM proximity check: \(distance)m from boarding stop")
        
        if distance < 250 {
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
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            if self.currentStopToMonitorId != nil || self.phase != .idle {
                self.authorizationDenied()
            }
        }
    }
    
    private func authorizationDenied() {
        continuation?.yield(.locationAuthorizationDenied)
        self.killManager()
    }

}

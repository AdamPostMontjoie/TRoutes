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

    private enum VehicleTrackingPhase {
        case idle
        case waitingToBoard
        case trackingVehicle
        case completed
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
            stopId: String? = nil,
            apiStopSequence: Int? = nil,
            routeId: String? = nil,
            status: String? = nil
        ) {
            self.currentVehicleId = vehicleId
            self.currentVehicleTrip = tripId
            self.currentVehicleStopId = stopId
            self.currentVehicleAPIStopSequence = apiStopSequence
            self.currentVehicleRouteId = routeId
            self.currentVehicleStatus = status
        }
    }

    private struct TrackedVehiclePosition {
        let vehicleStopId: String?
        let apiStopSequence: Int?
        let vehicleStatus: String?
        let legStopIndex: Int?
        let patternStopIndex: Int?
        let patternEdgeSequenceNumber: Int?
        let isBeforeOrigin: Bool
        let isAtOrigin: Bool
        let isBetweenOriginAndDestination: Bool
        let isAtDestination: Bool
        let isPastDestination: Bool

        init(
            vehicleStopId: String?,
            apiStopSequence: Int?,
            vehicleStatus: String?,
            legStop: ResolvedStop?,
            patternStop: ResolvedPatternStop?,
            leg: ResolvedLeg
        ) {
            self.vehicleStopId = vehicleStopId
            self.apiStopSequence = apiStopSequence
            self.vehicleStatus = vehicleStatus
            self.legStopIndex = legStop?.legStopIndex
            self.patternStopIndex = patternStop?.patternStopIndex ?? legStop?.patternStopIndex
            self.patternEdgeSequenceNumber = patternStop?.patternEdgeSequenceNumber ?? legStop?.patternEdgeSequenceNumber

            if let patternStopIndex = self.patternStopIndex {
                isBeforeOrigin = patternStopIndex < leg.originPatternStopIndex
                isAtOrigin = patternStopIndex == leg.originPatternStopIndex
                isBetweenOriginAndDestination = patternStopIndex > leg.originPatternStopIndex &&
                    patternStopIndex < leg.destinationPatternStopIndex
                isAtDestination = patternStopIndex == leg.destinationPatternStopIndex
                isPastDestination = patternStopIndex > leg.destinationPatternStopIndex
            } else {
                isBeforeOrigin = false
                isAtOrigin = false
                isBetweenOriginAndDestination = false
                isAtDestination = false
                isPastDestination = false
            }
        }
    }
    
    private var currentVehicle = TrackedVehicleState()
    private var currentLeg: ResolvedLeg?
    private var currentMatchedLegPath: MatchedLegPath?
    private var currentVehiclePosition: TrackedVehiclePosition?
    private var phase: VehicleTrackingPhase = .idle
    
    private var preparedCommand: JourneyCommand?
    private var continuation: AsyncStream<JourneyCommand>.Continuation?
    
    private var apiTimer: Timer?
    
    @Dependency(\.mbtaClient) var mbtaClient
    
    func makeEventStream() -> AsyncStream<JourneyCommand> {
        AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { _ in
                print("underground event stream termination")
            }
        }
    }

    func startSession() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .otherNavigation
        locationManager.startUpdatingLocation()

        guard currentVehicle.currentVehicleId != nil else { return }
        Task { await fetchVehicleData() }
    }
    
    //journey engine hands us a new vehicle to track
    func setTrackedVehicle(prediction: TransitPrediction, leg: ResolvedLeg) async {
        currentVehicle = TrackedVehicleState()
        currentVehicle.updateVehicleInfo(
            vehicleId: prediction.vehicleId,
            tripId: prediction.tripId,
            stopId: prediction.stopId,
            apiStopSequence: prediction.stopSequence,
            routeId: leg.mbtaRouteId
        )
        currentLeg = leg
        currentMatchedLegPath = nil
        currentVehiclePosition = nil
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
        updateVehicleData(with: vehicleData)
        if phase == .idle || phase == .completed{
            return
        }

        let tripId = vehicleData.tripId ?? currentVehicle.currentVehicleTrip
        let tripTrackingData: LiveTripTrackingData?
        if let tripId, currentMatchedLegPath?.tripId != tripId {
            tripTrackingData = await refreshTripTrackingData(tripId: tripId)
        } else {
            tripTrackingData = nil
        }
        
        updateVehiclePosition(with: vehicleData, tripTrackingData: tripTrackingData)
        printCurrentVehiclePosition()
        
        if phase == .waitingToBoard {
            evaluateBoardingProgress()
        }
        else if phase == .trackingVehicle {
            evaluateTrackedVehicleProgress()
        }

        if phase != .completed {
            setTimer(time: 15)
        }        
    }

    private func updateVehicleData(with vehicleData: VehicleData) {
        currentVehicle.updateVehicleInfo(
            vehicleId: currentVehicle.currentVehicleId,
            tripId: vehicleData.tripId ?? currentVehicle.currentVehicleTrip,
            stopId: vehicleData.stopId ?? currentVehicle.currentVehicleStopId,
            apiStopSequence: vehicleData.currentStopSequence ?? currentVehicle.currentVehicleAPIStopSequence,
            routeId: vehicleData.routeId ?? currentVehicle.currentVehicleRouteId,
            status: vehicleData.currentStatus ?? currentVehicle.currentVehicleStatus
        )
    }


    private func refreshTripTrackingData(tripId:String) async -> LiveTripTrackingData? {
        do {
            let tripTrackingData = try await mbtaClient.fetchTripTrackingData(tripId)
            currentVehicle.updateVehicleInfo(
                vehicleId: currentVehicle.currentVehicleId ?? tripTrackingData.vehicleId,
                tripId: tripTrackingData.tripId,
                stopId: currentVehicle.currentVehicleStopId ?? tripTrackingData.vehicleStopId,
                apiStopSequence: currentVehicle.currentVehicleAPIStopSequence ?? tripTrackingData.vehicleApiStopSequence,
                routeId: currentVehicle.currentVehicleRouteId,
                status: currentVehicle.currentVehicleStatus ?? tripTrackingData.vehicleStatus
            )
            // we need a new path once we get new trip data
            updateMatchedLegPath(tripTrackingData: tripTrackingData)
            return tripTrackingData
        } catch {
            handleVehicleFetchError(error: error)
            return nil
        }
    }

    private func updateMatchedLegPath(tripTrackingData:LiveTripTrackingData) {
        guard let currentLeg else {
            currentMatchedLegPath = nil
            return
        }

        guard currentMatchedLegPath?.matches(leg: currentLeg, tripId: tripTrackingData.tripId) != true else {
            return
        }

        currentMatchedLegPath = MatchedLegPath(
            leg: currentLeg,
            tripTrackingData: tripTrackingData
        )
    }

    private func updateVehiclePosition(with vehicleData: VehicleData, tripTrackingData: LiveTripTrackingData?) {
        guard let currentLeg,
              let currentMatchedLegPath else {
            currentVehiclePosition = nil
            return
        }

        let vehicleStopId = vehicleData.stopId ??
            tripTrackingData?.vehicleStopId ??
            currentVehicle.currentVehicleStopId
        let apiStopSequence = vehicleData.currentStopSequence ??
            tripTrackingData?.vehicleApiStopSequence ??
            currentVehicle.currentVehicleAPIStopSequence
        let vehicleStatus = (vehicleData.currentStatus ??
            tripTrackingData?.vehicleStatus ??
            currentVehicle.currentVehicleStatus)?.lowercased()

        let legStop = currentMatchedLegPath.legStop(forVehicleStopId: vehicleStopId)
        let patternStop = currentMatchedLegPath.patternStop(
            forVehicleStopId: vehicleStopId,
            apiStopSequence: apiStopSequence
        )

        currentVehiclePosition = TrackedVehiclePosition(
            vehicleStopId: vehicleStopId,
            apiStopSequence: apiStopSequence,
            vehicleStatus: vehicleStatus,
            legStop: legStop,
            patternStop: patternStop,
            leg: currentLeg
        )
    }

    private func evaluateBoardingProgress() {
        guard vehicleHasDepartedOrigin(),
              let originStopId = currentLeg?.startStop.stationId else {
            return
        }

        phase = .trackingVehicle
        continuation?.yield(.executeExit(stopId: originStopId))
        evaluateTrackedVehicleProgress()
    }

    private func evaluateTrackedVehicleProgress() {
        guard vehicleHasStoppedAtDestination(),
              let destinationStopId = currentLeg?.endStop.stationId else {
            return
        }

        phase = .completed
        cancelTimer()
        continuation?.yield(.executeEntry(stopId: destinationStopId))
    }

    private func vehicleHasDepartedOrigin() -> Bool {
        guard let currentVehiclePosition else { return false }
        return currentVehiclePosition.isBetweenOriginAndDestination ||
            currentVehiclePosition.isAtDestination ||
            currentVehiclePosition.isPastDestination
    }

    private func vehicleHasStoppedAtDestination() -> Bool {
        guard let currentVehiclePosition else { return false }
        return currentVehiclePosition.isAtDestination &&
            currentVehiclePosition.vehicleStatus == "stopped_at"
    }

    private func printCurrentVehiclePosition() {
        guard let currentLeg,
              let currentVehiclePosition else {
            return
        }

        let tripId = currentVehicle.currentVehicleTrip ?? currentMatchedLegPath?.tripId ?? "nil"
        let currentVehicleStopIdText = currentVehiclePosition.vehicleStopId ?? "nil"
        let currentVehicleAPIStopSequenceText = currentVehiclePosition.apiStopSequence.map(String.init) ?? "nil"
        let currentVehicleStatusText = currentVehiclePosition.vehicleStatus ?? "nil"
        let currentVehicleLegStopIndexText = currentVehiclePosition.legStopIndex.map(String.init) ?? "nil"
        let currentVehiclePatternIndexText = currentVehiclePosition.patternStopIndex.map(String.init) ?? "nil"
        let currentVehiclePatternEdgeSequenceText = currentVehiclePosition.patternEdgeSequenceNumber.map(String.init) ?? "nil"

        var output = """

        === Live Trip Tracking Match ===
        Trip:               \(tripId)
        Route:              \(currentLeg.mbtaRouteId)
        Direction:          \(currentLeg.mbtaDirectionId)
        Pattern:            \(currentLeg.selectedPatternId)
        Origin stop:         \(currentLeg.startStop.stationId)
        Origin leg stop index: \(currentLeg.startStop.legStopIndex)
        Origin pattern index: \(currentLeg.originPatternStopIndex)
        Origin pattern edge sequence: \(currentLeg.originPatternEdgeSequenceNumber)
        Destination stop:    \(currentLeg.endStop.stationId)
        Destination leg stop index: \(currentLeg.endStop.legStopIndex)
        Destination pattern index: \(currentLeg.destinationPatternStopIndex)
        Destination pattern edge sequence: \(currentLeg.destinationPatternEdgeSequenceNumber)
        Current stop:        \(currentVehicleStopIdText)
        Current API stop sequence: \(currentVehicleAPIStopSequenceText)
        Current API vehicle status:    \(currentVehicleStatusText)
        Current leg stop index: \(currentVehicleLegStopIndexText)
        Current pattern index: \(currentVehiclePatternIndexText)
        Current pattern edge sequence: \(currentVehiclePatternEdgeSequenceText)

        LEG_INDEX   PAT_INDEX   EDGE_SEQUENCE   PLATFORM        STATION
        -----------------------------------------------
        """

        for stop in currentLeg.stops {
            output += "\n\(stop.legStopIndex)     \(stop.patternStopIndex)     \(stop.patternEdgeSequenceNumber)     \(stop.platformId) \(stop.stopName)"
        }

//        output += """
//
//
//        FULL PATTERN
//        PAT_INDEX   EDGE_SEQUENCE   PLATFORM        STATION
//        -----------------------------------------------
//        """
//
//        for stop in currentLeg.patternStops {
//            output += "\n\(stop.patternStopIndex)     \(stop.patternEdgeSequenceNumber)     \(stop.platformId) \(stop.stopName)"
//        }

        output += "\n=========================="
        print(output)
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
        currentMatchedLegPath = nil
        currentVehiclePosition = nil
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


}

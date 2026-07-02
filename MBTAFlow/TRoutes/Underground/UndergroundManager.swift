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
    private var continuation: AsyncStream<UndergroundEvent>.Continuation?
    private var currentVehicle:String? //we need to track what train/bus we are supposed to be monitoring
    private var currentTrip:String?
    private var currentStopSequence:Int?
    private var currentRoute:String?
    private var currentLeg:Leg? //refine/specify later
    
    @Dependency(\.mbtaClient) var mbtaClient
    @Dependency(\.databaseClient) var databaseClient: DatabaseClient


    func makeEventStream() -> AsyncStream<UndergroundEvent> {
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
    }
    
    //journey engine hands us a vehicle to track
    //only should be done when we're at stop
    func updateTrackedVehicle(prediction: TransitPrediction, leg: Leg?) async {
        currentVehicle = prediction.vehicleId
        currentTrip = prediction.tripId
        currentStopSequence = prediction.stopSequence
        currentLeg = leg
        await fetchVehicleData()
    }

    func stopSession() {
        locationManager.stopUpdatingLocation()
        continuation?.finish()
        continuation = nil
    }
    
    //polls api for where the current vehicle is.
    //we will initially assume user always takes first available vehicle/vehicle of next time
    //this will not be accurate, so need to use incoming location data to determine
    private func fetchVehicleData() async {
        guard let vehicle = currentVehicle else { return }
        do {
            let data = try await mbtaClient.fetchVehicleData(vehicle)
            await handleVehicleData(data: data)
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
    private func handleVehicleData(data:VehicleData) async {
        currentRoute = data.routeId ?? currentRoute
        currentTrip = data.tripId ?? currentTrip
        currentStopSequence = data.currentStopSequence ?? currentStopSequence
        do {
            try await databaseClient.matchTripID(
                currentLeg?.mbtaRouteId ?? data.routeId,
                currentLeg?.transitDirection?.directionId ?? data.directionId,
                data.stopId,
                data.currentStopSequence ?? currentStopSequence,
                currentLeg?.startStop.mbtaStopId,
                currentLeg?.endStop.mbtaStopId
            )
        }
        
        catch {
            print("fuck")
        }
    }
    
    //if we can't get any info, that will be an error
    //specific enum will be defined, this is different than a prediction error
    private func handleVehicleFetchError(error: Error){
        
    }
    
    //dynamic, and it ending means it's time to fetch vehicle info again.
    private func setTimer(){
        
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

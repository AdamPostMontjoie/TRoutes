//
//  PositionReconciler.swift
//  TRoutes
//
//  Created by Adam Post on 7/8/26.
//

import ComposableArchitecture
import CoreLocation
import Foundation

///Attempts to handle state reconciliation if the app terminates in the background
actor PositionReconciler {
    
    @Dependency(\.mbtaClient) var mbtaClient
    
    enum ReconcileError: Error {
        case unableToReconcile
        case timeout
    }
    
    func reconcile(journey: JourneyState, currentLocation: CLLocation, trackedVehicleId: String?) async throws -> JourneyState {
        // Timeout check (30 minutes)
        if Date().timeIntervalSince(journey.timeSaved) > 1800 {
            throw ReconcileError.timeout
        }
        
        //Check if we can use the tracked vehicle.
        if let vehicleState = try? await reconcileWithTrackedVehicle(
            journey: journey,
            currentLocation: currentLocation,
            vehicleId: trackedVehicleId
        ) {
            return vehicleState
        }
        
        //Try to position inside of stops or between any stop.
        if let surfaceState = try? await reconcileWithSurfaceGPS(
            journey: journey,
            currentLocation: currentLocation
        ) {
            return surfaceState
        }
        
        //Yield a tracking error
        throw ReconcileError.unableToReconcile
    }
    
    private func reconcileWithTrackedVehicle(journey: JourneyState, currentLocation: CLLocation, vehicleId: String?) async throws -> JourneyState {
        guard let vehicleId = vehicleId else {
            throw ReconcileError.unableToReconcile
        }
        
        let vehicleData = try await mbtaClient.fetchVehicleData(vehicleId)
        
        guard let vehicleStopId = vehicleData.stopId,
              let vehicleLat = vehicleData.latitude,
              let vehicleLon = vehicleData.longitude else {
            throw ReconcileError.unableToReconcile
        }
        
        // Find if this stop exists in the journey's remaining stops of the current leg
        guard let matchedIndex = journey.stopOrder.firstIndex(where: { stop in
            stop.mbtaStopId == vehicleStopId || stop.platformId == vehicleStopId || stop.stationId == vehicleStopId
        }) else {
            throw ReconcileError.unableToReconcile
        }
        
        let matchedStop = journey.stopOrder[matchedIndex]
        
        // Ensure it's part of the current leg and we haven't already passed it
        guard matchedStop.legIndex == journey.legIndex,
              matchedIndex >= journey.stopIndex else {
            throw ReconcileError.unableToReconcile
        }
        
        // Check physical proximity to the vehicle (200 meters)
        let vehicleLocation = CLLocation(latitude: vehicleLat, longitude: vehicleLon)
        let distance = currentLocation.distance(from: vehicleLocation)
        
        guard distance <= 200 else {
            throw ReconcileError.unableToReconcile
        }
        
        var reconciledJourney = journey
        reconciledJourney.stopIndex = matchedIndex
        reconciledJourney.legIndex = matchedStop.legIndex
        reconciledJourney.monitoringMode = matchedStop.monitoringMode
        
        if vehicleData.currentStatus?.lowercased() == "stopped_at" {
            reconciledJourney.movementStatus = .atStop
        } else {
            reconciledJourney.movementStatus = .enRoute
        }
        
        print("PositionReconciler: Successfully reconciled with tracked vehicle \(vehicleId) at stop \(matchedStop.stopName)")
        return reconciledJourney
    }
    
    private func reconcileWithSurfaceGPS(journey: JourneyState, currentLocation: CLLocation) async throws -> JourneyState {
        // Let's find the closest upcoming stop in the current leg
        var closestStopIndex: Int?
        var minDistance: CLLocationDistance = Double.infinity
        
        for index in journey.stopIndex..<journey.stopOrder.count {
            let stop = journey.stopOrder[index]
            guard stop.legIndex == journey.legIndex else { break }
            
            let stopLoc = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let distance = currentLocation.distance(from: stopLoc)
            if distance < minDistance {
                minDistance = distance
                closestStopIndex = index
            }
        }
        
        guard let closestIndex = closestStopIndex else {
            throw ReconcileError.unableToReconcile
        }
        
        let closestStop = journey.stopOrder[closestIndex]
        
        // We only reconcile using GPS if the target stop is a surface stop
        guard closestStop.monitoringMode == .surface else {
            throw ReconcileError.unableToReconcile
        }
        
        var reconciledJourney = journey
        reconciledJourney.stopIndex = closestIndex
        reconciledJourney.monitoringMode = .surface
        
        // If we are close (<= 200m), we are at the stop. Otherwise, we are enRoute (going to it).
        if minDistance <= 200 {
            reconciledJourney.movementStatus = .atStop
        } else {
            reconciledJourney.movementStatus = .enRoute
        }
        
        print("PositionReconciler: Reconciled via surface GPS to stop \(closestStop.stopName) (distance: \(minDistance)m)")
        return reconciledJourney
    }
}

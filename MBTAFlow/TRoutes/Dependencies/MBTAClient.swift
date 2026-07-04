//
//  MBTAClient.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

//this will fetch whatever route times we need once we either A. Start a route B. Enter step location
struct MBTAClient {
    //predictions
    var fetchTransitTimes: @Sendable (Stop) async throws -> [TransitPrediction]
    var fetchDirections: @Sendable (String) async throws -> [TransitDirection]
    var fetchBranches: @Sendable (String, String) async throws -> [TransitBranch]
    var fetchStops: @Sendable (Int, String) async throws -> [Stop]
    var fetchRoutes: @Sendable (String, String) async throws -> String
    //position
    var fetchVehicleData: @Sendable (String) async throws -> VehicleData
    var fetchTripTrackingData: @Sendable (String) async throws -> LiveTripTrackingData
}



let header = "https://api-v3.mbta.com/"

//specific errors for alert display
enum MBTAError: Error, Equatable {
    case badRequest(String)
    case forbidden
    case rateLimited
    case serverError(Int)
    case timeoutError
    case decodingError
    case networkError
}

func reviewHttpResponse(_ response: URLResponse, _ data: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw MBTAError.networkError
    }
    switch httpResponse.statusCode {
    case 200...299:
        // Success! Proceed to decoding the prediction below.
        return
    case 400:
        // Decode the specific error payload to get the detail string
        let errorPayload = try? JSONDecoder().decode(MBTAErrorResponse.self, from: data)
        let detail = errorPayload?.errors.first?.detail ?? "Invalid request parameters."
        throw MBTAError.badRequest(detail)
    case 403:
        throw MBTAError.forbidden
    case 429:
        throw MBTAError.rateLimited
    default:
        // 500 errors
        throw MBTAError.serverError(httpResponse.statusCode)
    }
}

extension MBTAClient:DependencyKey {
    static let liveValue = Self(
        fetchTransitTimes: { stop in
            //filter out any that are in past and then return next 3.
            guard let url = URL(string: "\(header)predictions?filter[stop]=\(stop.mbtaStopId)&filter[direction_id]=\(stop.mbtaDirectionId)&filter[route]=\(stop.mbtaRouteId)&filter[revenue]=\("REVENUE")&sort=time&page[limit]=6") else {
                throw MBTAError.networkError
            }
         //   print("MBTAClient fetchTransitTimes URL: \(url.absoluteString)")
            
            // data and response type
            let (data, response) = try await URLSession.shared.data(from: url)
            
            try reviewHttpResponse(response, data)
            //Now it's safe to decode
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // 4. Decode the data into the structs
            do {
                let predictionResponse = try decoder.decode(PredictionResponse.self, from: data)
                
                
                // MBTA returns ISO8601 formatted strings (e.g., "2026-06-04T15:38:58-04:00")
                let isoFormatter = ISO8601DateFormatter()
                
                // We want to display standard times (e.g., "3:38 PM")
                let displayFormatter = DateFormatter()
                displayFormatter.timeStyle = .short
                
                let calendarComparator = Calendar.current
                let now = Date()
                var seenVehicleIds = Set<String>()
                var upcomingTimes: [TransitPrediction] = []
                
                for prediction in predictionResponse.data {
                    let display: String
                    
                    // 1. Physical signs prioritize specific statuses over timestamps
                    if let status = prediction.attributes.status {
                        display = status
                    } else if let timeString = prediction.attributes.arrivalTime ?? prediction.attributes.departureTime,
                              let date = isoFormatter.date(from: timeString),
                              date >= now {
                        // 2. If no status, calculate the "minutes away" countdown
                        let minutesAway = calendarComparator.dateComponents([.minute], from: now, to: date).minute ?? 0
                        display = minutesAway <= 0 ? "Arriving" : "\(minutesAway) min"
                    } else {
                        continue
                    }
                    
                    let vehicleId = prediction.relationships.vehicle?.data?.id
                    if let vehicleId, !seenVehicleIds.insert(vehicleId).inserted {
                        continue
                    }
                    
                    upcomingTimes.append(
                        TransitPrediction(
                            display: display,
                            vehicleId: vehicleId,
                            predictionId: prediction.id,
                            tripId: prediction.relationships.trip?.data?.id,
                            stopId: prediction.relationships.stop?.data?.id,
                            directionId: prediction.attributes.directionId,
                            stopSequence: prediction.attributes.stopSequence
                        )
                    )
                    
                    if upcomingTimes.count == 3 {
                        break
                    }
                }
                
                return upcomingTimes
            } catch {
                throw MBTAError.decodingError
            }
        },
       
        fetchDirections: { routeId in
                    guard let url = URL(string: "\(header)routes?filter[id]=\(routeId)&fields[route]=direction_names,direction_destinations,short_name,long_name") else {
                        throw MBTAError.networkError
                    }
          //          print("MBTAClient fetchDirections URL: \(url.absoluteString)")
                    
                    let (data, response) = try await URLSession.shared.data(from: url)
                    try reviewHttpResponse(response,data)
                    
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    
                    do {
                        let routeResponse = try decoder.decode(RouteListResponse.self, from: data)
                        
                        guard let route = routeResponse.data.first,
                              let names = route.attributes.directionNames,
                              let destinations = route.attributes.directionDestinations else {
                            return [] // Return empty if no directions found
                        }
                        
                        var mappedDirections: [TransitDirection] = []
                        for index in 0..<names.count {
                            if index < destinations.count {
                                mappedDirections.append(
                                    TransitDirection(directionId: index, directionName: names[index], destination: destinations[index])
                                )
                            }
                        }
                        // Return an array of TransitDirection directly to the Reducer
                        return mappedDirections
                    } catch {
                        throw MBTAError.decodingError
                    }
                },
    
        //for use on lines that don't have a single direction
        fetchBranches: { filterKey, filterValue in
            guard let url = URL(string: "\(header)routes?\(filterKey)=\(filterValue)&fields[route]=short_name,long_name,direction_names,direction_destinations") else {
                throw MBTAError.networkError
            }
       //     print("MBTAClient fetchBranches URL: \(url.absoluteString)")
            
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response,  data)
                
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let routeResponse = try decoder.decode(RouteListResponse.self, from: data)
                
                // Map the raw JSON data into the clean struct for the UI
                let branches = routeResponse.data.compactMap{ route -> TransitBranch? in
                    let short = route.attributes.shortName ?? ""
                    let display = short.isEmpty ? (route.attributes.longName ?? "Route") : short
                    if display == "Mattapan Line" {
                        return nil
                    }
                    
                    // Safely extract the directions. MBTA always returns 0 first, then 1.
                    var mappedDirections: [TransitDirection] = []
                    
                    if let names = route.attributes.directionNames,
                       let destinations = route.attributes.directionDestinations {
                        // Iterate through the arrays (index 0 is direction_id 0, index 1 is direction_id 1)
                        for index in 0..<names.count {
                            // Some bus routes only go one way, so we safely check bounds
                            if index < destinations.count {
                                let direction = TransitDirection(
                                    directionId: index,
                                    directionName: names[index],
                                    destination: destinations[index]
                                )
                                mappedDirections.append(direction)
                            }
                        }
                    }
                    
                    return TransitBranch(id: route.id, displayName: display, directions: mappedDirections)
                }
                
                return branches
            } catch {
                throw MBTAError.decodingError
            }
        },
        fetchStops: { directionId, routeId in
            guard let url = URL(string: "\(header)stops?filter[route]=\(routeId)&filter[direction_id]=\(directionId)&fields[stop]=name,latitude,longitude,address") else {
                            throw MBTAError.networkError
                        }
       //                 print("MBTAClient fetchStops URL: \(url.absoluteString)")
                        
                        let (data, response) = try await URLSession.shared.data(from: url)
                        try reviewHttpResponse(response, data)
                        
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        
                        do {
                            let stopResponse = try decoder.decode(StopListResponse.self, from: data)
                            
                            var stops: [Stop] = []
                            let totalStops = stopResponse.data.count
                            
                            for (index, stopData) in stopResponse.data.enumerated() {
                                let stop = Stop(
                                    id: UUID(),
                                    mbtaStopId: stopData.id,
                                    mbtaRouteId: routeId,
                                    mbtaDirectionId: directionId,
                                    stopName: stopData.attributes.name ?? "stop",
                                    longitude: stopData.attributes.longitude ?? 0.0,
                                    latitude: stopData.attributes.latitude ?? 0.0,
                                    address: stopData.attributes.address ?? "Boston, MA",
                                    journeyRole: .boarding
                                )
                                stops.append(stop)
                            }
                            
                            return stops
                        } catch {
                            throw MBTAError.decodingError
                        }
        },
        fetchRoutes: { filterKey,filterValue in
            
            return "routes"
        },
        fetchVehicleData: { vehicleId in
            guard let encodedVehicleId = vehicleId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(header)vehicles/\(encodedVehicleId)") else {
                throw MBTAError.networkError
            }
            print("MBTAClient fetchVehicle URL: \(url.absoluteString)")
            
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let vehicleResponse = try decoder.decode(VehicleResponse.self, from: data)
                let attributes = vehicleResponse.data.attributes
                return VehicleData(
                    id: vehicleResponse.data.id,
                    bearing: attributes.bearing,
                    directionId: attributes.directionId,
                    routeId: vehicleResponse.data.relationships?.route?.data?.id,
                    tripId: vehicleResponse.data.relationships?.trip?.data?.id,
                    stopId: vehicleResponse.data.relationships?.stop?.data?.id,
                    latitude: attributes.latitude,
                    longitude: attributes.longitude,
                    currentStopSequence: attributes.currentStopSequence,
                    currentStatus: attributes.currentStatus,
                    speed: attributes.speed
                )
            } catch {
                throw MBTAError.decodingError
            }
        },

        fetchTripTrackingData: { tripId in
            guard let encodedTripId = tripId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(header)trips/\(encodedTripId)?include=stops,predictions,vehicle,route_pattern") else {
                throw MBTAError.networkError
            }
            print("MBTAClient fetchTripTrackingData URL: \(url.absoluteString)")

            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            do {
                let tripResponse = try decoder.decode(TripTrackingResponse.self, from: data)
                return makeLiveTripTrackingData(from: tripResponse)
            } catch {
                throw MBTAError.decodingError
            }
        }
    )
    static let testValue: Self = .liveValue //TODO figure out what the hell this is even about later
}

extension DependencyValues {
    var mbtaClient: MBTAClient {
        get { self[MBTAClient.self] }
        set { self[MBTAClient.self] = newValue }
    }
}

private func makeLiveTripTrackingData(from response: TripTrackingResponse) -> LiveTripTrackingData {
    let included = response.included ?? []
    let includedById = Dictionary(uniqueKeysWithValues: included.map { ($0.id, $0) })
    let vehicleId = response.data.relationships.vehicle?.data?.id
    let includedVehicle = vehicleId.flatMap { includedById[$0] }
    let stopNodes = response.data.relationships.stops?.data ?? []
    let predictionNodes = response.data.relationships.predictions?.data ?? []

    let stops = stopNodes.enumerated().compactMap { index, node -> LiveTripStop? in
        guard node.type == "stop" else { return nil }
        let includedStop = includedById[node.id]
        return LiveTripStop(
            stopId: node.id,
            parentStationId: includedStop?.relationships?.parentStation?.data?.id,
            name: includedStop?.attributes?.name,
            orderIndex: index
        )
    }

    let predictions = predictionNodes.compactMap { node -> LiveTripPrediction? in
        guard node.type == "prediction",
              let includedPrediction = includedById[node.id],
              let stopId = includedPrediction.relationships?.stop?.data?.id else {
            return nil
        }

        return LiveTripPrediction(
            stopId: stopId,
            apiStopSequence: includedPrediction.attributes?.stopSequence,
            arrivalTime: includedPrediction.attributes?.arrivalTime,
            departureTime: includedPrediction.attributes?.departureTime
        )
    }

    return LiveTripTrackingData(
        tripId: response.data.id,
        vehicleId: vehicleId,
        routePatternId: response.data.relationships.routePattern?.data?.id,
        vehicleStopId: includedVehicle?.relationships?.stop?.data?.id,
        vehicleStatus: includedVehicle?.attributes?.currentStatus,
        vehicleApiStopSequence: includedVehicle?.attributes?.currentStopSequence,
        stops: stops,
        predictions: predictions
    )
}


func parseMBTAPredictionJSON(jsonData: Data) {
    let decoder = JSONDecoder()
    
    // This tells the decoder to automatically convert "arrival_time" to "arrivalTime"
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    do {
        // Attempt to decode the raw Data into the root PredictionResponse struct
        let response = try decoder.decode(PredictionResponse.self, from: jsonData)
        
        // Access the parsed data
        for prediction in response.data {
            let id = prediction.id
            let status = prediction.attributes.status ?? "No status"
            let stopId = prediction.relationships.stop?.data?.id ?? "Unknown Stop"
            
            print("Prediction \(id): \(status) at Stop \(stopId)")
        }
        
    } catch {
        print("Failed to decode JSON: \(error)")
    }
}

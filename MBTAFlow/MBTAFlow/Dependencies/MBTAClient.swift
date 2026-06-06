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
    var fetchTransitTimes: @Sendable (Stop) async throws -> [String]
    var fetchDirections: @Sendable (String) async throws -> [TransitDirection]
    //for use on lines that don't have a single direction
    var fetchBranches: @Sendable (String, String) async throws -> [TransitBranch]
    var fetchStops: @Sendable (Int, String) async throws -> [Stop]
    var fetchRoutes: @Sendable (String, String) async throws -> String
}

let header = "https://api-v3.mbta.com/"

//specific errors for alert display
enum MBTAError: Error, Equatable {
    case badRequest(String)
    case forbidden
    case rateLimited
    case serverError(Int)
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
            // 1. Construct the URL using the correct MBTA identifiers
            guard let url = URL(string: "\(header)predictions?filter[stop]=\(stop.mbtaStopId)&filter[route]=\(stop.mbtaRouteId)&filter[revenue]=\("REVENUE")&sort=time&page[limit]=3") else {
                throw URLError(.badURL)
            }
            
            // data and response type
            let (data, response) = try await URLSession.shared.data(from: url)
            
            try reviewHttpResponse(response, data)
            //Now it's safe to decode
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // 4. Decode the data into the structs
            do {
                let predictionResponse = try decoder.decode(PredictionResponse.self, from: data)
                
                // 5. Format the output
                var upcomingTimes: [String] = []
                
                // MBTA returns ISO8601 formatted strings (e.g., "2026-06-04T15:38:58-04:00")
                let isoFormatter = ISO8601DateFormatter()
                
                // We want to display standard times (e.g., "3:38 PM")
                let displayFormatter = DateFormatter()
                displayFormatter.timeStyle = .short
                
                for prediction in predictionResponse.data {
                    // If it's the first stop on a route, arrivalTime is null, so fallback to departureTime
                    if let timeString = prediction.attributes.arrivalTime ?? prediction.attributes.departureTime,
                       let date = isoFormatter.date(from: timeString) {
                        
                        let readableTime = displayFormatter.string(from: date)
                        upcomingTimes.append(readableTime)
                        
                    } else if let status = prediction.attributes.status {
                        // Fallback: If there is no exact time, the MBTA might just provide a status like "Approaching"
                        upcomingTimes.append(status)
                    }
                }
                return upcomingTimes
            } catch {
                throw MBTAError.decodingError
            }
        },
        //this will be called immediately if red line, etc, but after if it's green line. both use routes endpoint
       
        fetchDirections: { routeId in
                    // If the user selected Blue Line, routeId is "Blue or sum shit"
                    guard let url = URL(string: "\(header)routes?filter[id]=\(routeId)&fields[route]=direction_names,direction_destinations,short_name,long_name") else {
                        throw URLError(.badURL)
                    }
                    
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
    
        //this is required for green line, bus, cr, ferry
        fetchBranches: { filterKey, filterValue in
            // Added direction_names and direction_destinations to the fields filter
            guard let url = URL(string: "\(header)routes?\(filterKey)=\(filterValue)&fields[route]=short_name,long_name,direction_names,direction_destinations") else {
                throw URLError(.badURL)
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response,  data)
                
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let routeResponse = try decoder.decode(RouteListResponse.self, from: data)
                
                // Map the raw JSON data into the clean struct for the UI
                let branches = routeResponse.data.map { route in
                    let short = route.attributes.shortName ?? ""
                    let display = short.isEmpty ? (route.attributes.longName ?? "Route") : short
                    
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
                            throw URLError(.badURL)
                        }
                        
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
                                    stopName: stopData.attributes.name ?? "stop",
                                    longitude: stopData.attributes.longitude ?? 0.0,
                                    latitude: stopData.attributes.latitude ?? 0.0,
                                    lastStop: false, //needs to be set true by user saving
                                    // Address is often null for subway stations, fallback prevents decoding crashes
                                    address: stopData.attributes.address ?? "Boston, MA"
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

//
//  MBTAClient.swift
//  TRoutes
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import Foundation

struct MBTAClient {
    //predictions and schedules
    var fetchTransitTimes: @Sendable (ResolvedStop, [String], MBTARequestType) async throws -> [TransitPrediction]
    var fetchSchedule: @Sendable (ResolvedStop, MBTARequestType) async throws -> [TransitSchedule]
    //form
    var fetchDirections: @Sendable (String, MBTARequestType) async throws -> [TransitDirection]
    var fetchBranches: @Sendable (String, String, MBTARequestType) async throws -> [TransitBranch]
    var fetchStops: @Sendable (Int, String, MBTARequestType) async throws -> [Stop]
    //position and matching
    var fetchVehicleData: @Sendable (String, MBTARequestType) async throws -> VehicleData
    var fetchTripPathData: @Sendable (String, MBTARequestType) async throws -> LiveTripPath
}



let header = "https://api-v3.mbta.com/"

//specific errors for alert display
enum MBTAError: Error, Equatable {
    case badRequest(String)
    case forbidden
    case rateLimited
    case rateLimitDropped
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
        print("rate limited, didn't drop")
        throw MBTAError.rateLimited
    default:
        // 500 errors
        throw MBTAError.serverError(httpResponse.statusCode)
    }
}

extension MBTAClient:DependencyKey {
    static let liveValue = Self(
        fetchTransitTimes: { stop, routeIds, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                print("dropped request")
                throw MBTAError.rateLimitDropped
            }
            // Use comma-separated route IDs for multi-branch filtering
            let routeFilter = routeIds.isEmpty ? stop.mbtaRouteId : routeIds.joined(separator: ",")
            guard let url = URL(string: "\(header)predictions?filter[stop]=\(stop.mbtaStopId)&filter[direction_id]=\(stop.mbtaDirectionId)&filter[route]=\(routeFilter)&filter[revenue]=\("REVENUE")&sort=time&page[limit]=15") else {
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
                    } else {
                        let arrivalDate = prediction.attributes.arrivalTime.flatMap { isoFormatter.date(from: $0) }
                        let departureDate = prediction.attributes.departureTime.flatMap { isoFormatter.date(from: $0) }
                        
                        // It is dwelling if arrival is in the past but departure is in the future
                        let isDwelling = (arrivalDate != nil && arrivalDate! < now) && (departureDate != nil && departureDate! >= now)
                        
                        if isDwelling {
                            display = "Boarding"
                        } else if let date = arrivalDate ?? departureDate, date >= now {
                            // 2. If no status, calculate the "minutes away" countdown
                            let minutesAway = calendarComparator.dateComponents([.minute], from: now, to: date).minute ?? 0
                            display = minutesAway <= 0 ? "Arriving" : "\(minutesAway) min"
                        } else {
                            continue
                        }
                    }
                    let routeId = prediction.relationships.route?.data?.id
                    
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
                            routeId: routeId,
                            headsign: prediction.attributes.tripHeadsign,
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
        fetchSchedule: { stop, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
            
            // Format current time as HH:mm to filter out past schedules for today
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
            let minTime = dateFormatter.string(from: Date())
            
            guard let url = URL(string: "\(header)schedules?filter[stop]=\(stop.mbtaStopId)&filter[direction_id]=\(stop.mbtaDirectionId)&filter[route]=\(stop.mbtaRouteId)&filter[min_time]=\(minTime)&sort=time&page[limit]=3") else {
                throw MBTAError.networkError
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let scheduleResponse = try decoder.decode(ScheduleResponse.self, from: data)
                let isoFormatter = ISO8601DateFormatter()
                
                let displayFormatter = DateFormatter()
                displayFormatter.timeStyle = .short
                displayFormatter.timeZone = TimeZone.current
                
                var upcomingSchedules: [TransitSchedule] = []
                
                for schedule in scheduleResponse.data {
                    let dateStr = schedule.attributes.departureTime ?? schedule.attributes.arrivalTime
                    guard let dateStr = dateStr, let date = isoFormatter.date(from: dateStr) else { continue }
                    
                    let display = displayFormatter.string(from: date)
                    
                    let transitSchedule = TransitSchedule(
                        display: display,
                        vehicleId: schedule.relationships.vehicle?.data?.id,
                        ScheduleId: schedule.id,
                        tripId: schedule.relationships.trip?.data?.id,
                        stopId: schedule.relationships.stop?.data?.id,
                        routeId: schedule.relationships.route?.data?.id,
                        headsign: schedule.attributes.tripHeadsign,
                        directionId: schedule.attributes.directionId,
                        stopSequence: schedule.attributes.stopSequence
                    )
                    upcomingSchedules.append(transitSchedule)
                }
                
                return upcomingSchedules
            } catch {
                throw MBTAError.decodingError
            }
        },
        fetchDirections: { routeId, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
            guard let url = URL(string: "\(header)routes?filter[id]=\(routeId)&fields[route]=direction_names,direction_destinations,short_name,long_name") else {
                throw MBTAError.networkError
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let routeResponse = try decoder.decode(RouteListResponse.self, from: data)
                guard let route = routeResponse.data.first,
                      let names = route.attributes.directionNames,
                      let destinations = route.attributes.directionDestinations else {
                    return []
                }
                var mappedDirections: [TransitDirection] = []
                for index in 0..<names.count {
                    if index < destinations.count {
                        mappedDirections.append(
                            TransitDirection(directionId: index, directionName: names[index], destination: destinations[index])
                        )
                    }
                }
                return mappedDirections
            } catch {
                throw MBTAError.decodingError
            }
        },
        fetchBranches: { filterKey, filterValue, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
            guard let url = URL(string: "\(header)routes?\(filterKey)=\(filterValue)&fields[route]=short_name,long_name,direction_names,direction_destinations") else {
                throw MBTAError.networkError
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let routeResponse = try decoder.decode(RouteListResponse.self, from: data)
                let branches = routeResponse.data.compactMap { route -> TransitBranch? in
                    let short = route.attributes.shortName ?? ""
                    let display = short.isEmpty ? (route.attributes.longName ?? "Route") : short
                    if display == "Mattapan Line" { return nil }
                    var mappedDirections: [TransitDirection] = []
                    if let names = route.attributes.directionNames,
                       let destinations = route.attributes.directionDestinations {
                        for index in 0..<names.count where index < destinations.count {
                            mappedDirections.append(
                                TransitDirection(directionId: index, directionName: names[index], destination: destinations[index])
                            )
                        }
                    }
                    return TransitBranch(id: route.id, displayName: display, directions: mappedDirections)
                }
                return branches
            } catch {
                throw MBTAError.decodingError
            }
        },
        fetchStops: { directionId, routeId, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
            guard let url = URL(string: "\(header)stops?filter[route]=\(routeId)&filter[direction_id]=\(directionId)&fields[stop]=name,latitude,longitude,address") else {
                throw MBTAError.networkError
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let stopResponse = try decoder.decode(StopListResponse.self, from: data)
                return stopResponse.data.map { stopData in
                    Stop(
                        id: UUID(),
                        mbtaStopId: stopData.id,
                        mbtaRouteId: routeId,
                        mbtaDirectionId: directionId,
                        stopName: stopData.attributes.name ?? "stop",
                        longitude: stopData.attributes.longitude ?? 0.0,
                        latitude: stopData.attributes.latitude ?? 0.0,
                        address: stopData.attributes.address ?? "Boston, MA"
                    )
                }
            } catch {
                throw MBTAError.decodingError
            }
        },
        fetchVehicleData: { vehicleId, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
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

        fetchTripPathData: { tripId, requestType in
            do {
                try await RateLimitQueue.shared.acquireToken(for: requestType)
            } catch {
                throw MBTAError.rateLimitDropped
            }
            
            guard let encodedTripId = tripId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(header)trips/\(encodedTripId)?include=stops,predictions,vehicle,route_pattern") else {
                throw MBTAError.networkError
            }
            print("MBTAClient fetchTripPathData URL: \(url.absoluteString)")

            let (data, response) = try await URLSession.shared.data(from: url)
            try reviewHttpResponse(response, data)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            do {
                let tripResponse = try decoder.decode(TripPathResponse.self, from: data)
                return makeLiveTripPath(from: tripResponse)
            } catch {
                throw MBTAError.decodingError
            }
        }
    )
}

extension DependencyValues {
    var mbtaClient: MBTAClient {
        get { self[MBTAClient.self] }
        set { self[MBTAClient.self] = newValue }
    }
}

private func makeLiveTripPath(from response: TripPathResponse) -> LiveTripPath {
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

    return LiveTripPath(
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

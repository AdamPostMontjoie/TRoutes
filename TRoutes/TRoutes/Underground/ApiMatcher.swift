//
//  ApiMatcher.swift
//  TRoutes
//
//  Created by Adam Post on 7/4/26.
//
import Foundation

struct MatchedLegPath {
    let sourceLegId: UUID
    let selectedPatternId: String
    let acceptablePatternIds: Set<String>
    let tripId: String
    let legStopByStopId: [String: ResolvedStop]
    let patternStopByStopId: [String: ResolvedPatternStop]
    let patternStopByEdgeSequenceNumber: [Int: ResolvedPatternStop]
    let parentStationIdByTripStopId: [String: String]

    init(leg: ResolvedLeg, tripPath: LiveTripPath) {
        sourceLegId = leg.sourceLegId
        selectedPatternId = leg.selectedPatternId
        acceptablePatternIds = Set(leg.acceptablePatternIds)
        tripId = tripPath.tripId

        var legStopByStopId: [String: ResolvedStop] = [:]
        for stop in leg.stops {
            legStopByStopId[stop.mbtaStopId] = stop
            legStopByStopId[stop.platformId] = stop
            legStopByStopId[stop.stationId] = stop
        }
        self.legStopByStopId = legStopByStopId

        var patternStopByStopId: [String: ResolvedPatternStop] = [:]
        var patternStopByEdgeSequenceNumber: [Int: ResolvedPatternStop] = [:]
        for stop in leg.patternStops {
            patternStopByStopId[stop.platformId] = stop
            patternStopByStopId[stop.stationId] = stop
            patternStopByEdgeSequenceNumber[stop.patternEdgeSequenceNumber] = stop
        }
        self.patternStopByStopId = patternStopByStopId
        self.patternStopByEdgeSequenceNumber = patternStopByEdgeSequenceNumber

        var parentStationIdByTripStopId: [String: String] = [:]
        for stop in tripPath.stops {
            if let parentStationId = stop.parentStationId {
                parentStationIdByTripStopId[stop.stopId] = parentStationId
            }
        }
        self.parentStationIdByTripStopId = parentStationIdByTripStopId
    }

    func matches(leg: ResolvedLeg, tripId: String) -> Bool {
        sourceLegId == leg.sourceLegId &&
        self.tripId == tripId
    }

    /// Whether a given pattern ID is acceptable for this leg
    func acceptsPattern(_ patternId: String) -> Bool {
        acceptablePatternIds.contains(patternId) || patternId == selectedPatternId
    }

    func legStop(forVehicleStopId stopId: String?) -> ResolvedStop? {
        guard let stopId else { return nil }
        if let stop = legStopByStopId[stopId] {
            return stop
        }

        guard let parentStationId = parentStationIdByTripStopId[stopId] else {
            return nil
        }

        return legStopByStopId[parentStationId]
    }

    func patternStop(
        forVehicleStopId stopId: String?,
        apiStopSequence: Int?
    ) -> ResolvedPatternStop? {
        if let stopId {
            if let stop = patternStopByStopId[stopId] {
                return stop
            }

            if let parentStationId = parentStationIdByTripStopId[stopId],
               let stop = patternStopByStopId[parentStationId] {
                return stop
            }
        }

        guard let apiStopSequence else { return nil }
        return patternStopByEdgeSequenceNumber[apiStopSequence]
    }
}

//
//  ResolvedUserRouteFormMapping.swift
//  TRoutes
//
//  Created by Adam Post on 7/4/26.
//

import Foundation

func makeUserRouteForEditing(from resolvedRoute: ResolvedUserRoute) -> UserRoute {
    UserRoute(
        legs: resolvedRoute.legs.map(makeLegForEditing),
        id: resolvedRoute.id,
        name: resolvedRoute.name,
        timeStamp: resolvedRoute.timeStamp
    )
}

private func makeLegForEditing(from resolvedLeg: ResolvedLeg) -> Leg {
    Leg(
        id: resolvedLeg.sourceLegId,
        startStop: makeStopForEditing(from: resolvedLeg.startStop),
        endStop: makeStopForEditing(from: resolvedLeg.endStop),
        mbtaRouteId: resolvedLeg.mbtaRouteId,
        transitType: resolvedLeg.transitType,
        transitBranch: resolvedLeg.transitBranch,
        transitDirection: resolvedLeg.transitDirection,
        selectedRouteIds: resolvedLeg.acceptableRouteIds.isEmpty ? nil : resolvedLeg.acceptableRouteIds
    )
}

private func makeStopForEditing(from resolvedStop: ResolvedStop) -> Stop {
    Stop(
        id: resolvedStop.id,
        mbtaStopId: resolvedStop.stationId,
        mbtaRouteId: resolvedStop.mbtaRouteId,
        mbtaDirectionId: resolvedStop.mbtaDirectionId,
        stopName: resolvedStop.stopName,
        longitude: resolvedStop.longitude,
        latitude: resolvedStop.latitude,
        address: resolvedStop.address,
        journeyRole: resolvedStop.journeyRole
    )
}

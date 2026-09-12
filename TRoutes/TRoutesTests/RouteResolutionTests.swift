import Testing
@testable import TRoutes

struct RouteResolutionTests {
    @Test func singleGreenBranchUsesSelectedRoute() {
        #expect(
            routeIdsForResolution(
                selectedRouteIds: nil,
                selectedRouteId: "Green-E",
                transitType: .greenLine
            ) == ["Green-E"]
        )
    }

    @Test func explicitGreenBranchesRemainSelected() {
        #expect(
            routeIdsForResolution(
                selectedRouteIds: ["Green-D", "Green-E"],
                selectedRouteId: "Green-D",
                transitType: .greenLine
            ) == ["Green-D", "Green-E"]
        )
    }

    @Test func fixedRouteTypeUsesItsRouteIds() {
        #expect(
            routeIdsForResolution(
                selectedRouteIds: nil,
                selectedRouteId: "Red",
                transitType: .redLine
            ) == ["Red"]
        )
    }
}
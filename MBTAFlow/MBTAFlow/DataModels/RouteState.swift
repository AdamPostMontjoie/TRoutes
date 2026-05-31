//
//  RouteState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

//determine what we might need or if this is even a good idea to have
struct RouteState: Equatable {
    var route: RouteStruct
    var numberOfStops: Int
    var currentStop:Stop
    var onStop: Bool
    
    init(route: RouteStruct) {
        self.route = route
        self.numberOfStops = route.stops.count
        self.currentStop = route.stops.first!
        self.onStop = true //here we would do a check with the dependency 
    }
}

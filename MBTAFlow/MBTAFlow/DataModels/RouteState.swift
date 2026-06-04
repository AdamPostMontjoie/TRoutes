//
//  RouteState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct RouteState: Equatable {
    var route: RouteStruct
    var numberOfStops: Int
    var currentStop:StopState
    
    init(route: RouteStruct) {
        self.route = route
        self.numberOfStops = route.stops.count
        self.currentStop = StopState(stop:route.stops.first!)

    }
    
}

struct StopState:Equatable {
    var stop: Stop
    var nextTimes: [String]?
    var delayed: Bool = false
    var onStop: Bool = false
    
    init(stop: Stop) {
        self.stop = stop
    }
}

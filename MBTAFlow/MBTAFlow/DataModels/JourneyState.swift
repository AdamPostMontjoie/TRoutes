//
//  JourneyState.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/31/26.
//

struct JourneyState: Equatable {
    var route: RouteStruct
    var numberOfLegs: Int
    var currentLeg:LegState
    
    init(route: RouteStruct) {
        self.route = route
        self.numberOfLegs = route.legs.count
        self.currentLeg = LegState.init(leg: route.legs.first!, stops: [])

    }
    
}

struct LegState:Equatable {
    var leg: Leg
    var currentStop:StopState
    init(leg: Leg, stops: [StopState]) {
        self.leg = leg
        self.currentStop = StopState.init(stop: leg.startStop)
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

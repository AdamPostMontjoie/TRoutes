//
//  JourneyAttributes.swift
//  TRoutes
//
//  Created by Adam Post on 7/17/26.
//

import ActivityKit

struct JourneyAttributes: ActivityAttributes {
    let routeName: String
    public struct ContentState: Codable, Hashable {
        
        var context:String
        var times: [String]
    }
    
    var orderNumber: String
}

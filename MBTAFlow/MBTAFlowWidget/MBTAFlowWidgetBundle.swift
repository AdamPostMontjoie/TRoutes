//
//  MBTAFlowWidgetBundle.swift
//  MBTAFlowWidget
//
//  Created by Adam Post on 5/25/26.
//

import WidgetKit
import SwiftUI

@main
struct MBTAFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        MBTAFlowWidget()
        MBTAFlowWidgetControl()
        MBTAFlowWidgetLiveActivity()
    }
}

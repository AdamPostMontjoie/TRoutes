//
//  TRoutesWidgetLiveActivity.swift
//  TRoutesWidget
//
//  Created by Adam Post on 5/25/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TRoutesWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct TRoutesWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TRoutesWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension TRoutesWidgetAttributes {
    fileprivate static var preview: TRoutesWidgetAttributes {
        TRoutesWidgetAttributes(name: "World")
    }
}

extension TRoutesWidgetAttributes.ContentState {
    fileprivate static var smiley: TRoutesWidgetAttributes.ContentState {
        TRoutesWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: TRoutesWidgetAttributes.ContentState {
         TRoutesWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: TRoutesWidgetAttributes.preview) {
   TRoutesWidgetLiveActivity()
} contentStates: {
    TRoutesWidgetAttributes.ContentState.smiley
    TRoutesWidgetAttributes.ContentState.starEyes
}

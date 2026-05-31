//
//  ActiveRouteDisplayView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

//this needs to look at least somewhat like the liveactivity

struct ActiveRouteDisplayView: View {
    let store: StoreOf<ActiveRouteDisplayFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.route?.name ?? "")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .padding()
    }
}

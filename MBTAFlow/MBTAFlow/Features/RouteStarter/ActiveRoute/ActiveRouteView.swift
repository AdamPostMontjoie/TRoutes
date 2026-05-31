//
//  ActiveRouteView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct ActiveRouteView: View {
    let store: StoreOf<ActiveRouteFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.title)
                .font(.headline)
            Text(store.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .padding()
    }
}

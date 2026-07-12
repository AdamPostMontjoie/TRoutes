//
//  LegRowView.swift
//  TRoutes
//
//  Created by Adam Post on 6/7/26.
//

import ComposableArchitecture
import SwiftUI

struct LegRowView: View {
    let store: StoreOf<LegRowFeature>

    var body: some View {
        HStack(spacing: 12) {
            Text(store.leg.startStop.stopName)
                .frame(maxWidth: .infinity, alignment: .leading)
                
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Text(store.leg.endStop.stopName)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button {
                store.send(.editButtonTapped)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button {
                store.send(.deleteButtonTapped)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

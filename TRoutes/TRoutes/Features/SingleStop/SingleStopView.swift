//
//  SingleStopView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import SwiftUI
import ComposableArchitecture

struct SingleStopView: View {
    @Bindable var store: StoreOf<SingleStopFeature>
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("Single Stop Tab")
                    .font(.headline)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Single Stop")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

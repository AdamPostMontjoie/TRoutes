//
//  SelectorView.swift
//  MBTAFlow
//
//  Created by Adam Post on 5/25/26.
//

import ComposableArchitecture
import SwiftUI

struct SelectorView: View {
    let store: StoreOf<SelectorFeature>

    var body: some View {
        List(store.items) { item in
            Text(item.name)
        }
        .listStyle(.plain)
    }
}

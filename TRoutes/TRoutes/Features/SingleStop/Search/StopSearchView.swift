//
//  StopSearchView.swift
//  TRoutes
//
//  Created by Adam Post on 8/17/26.
//

import SwiftUI
import ComposableArchitecture

struct StopSearchView: View {
    @Bindable var store: StoreOf<StopSearchFeature>
    
    var body: some View {
        List {
            ForEach(store.results) { station in
                Button {
                    store.send(.stationTapped(station))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.stationName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 6) {
                            let uniqueTypes = Array(Set(station.stops.map(\.transitType)))
                                .sorted { $0.sortOrder < $1.sortOrder }
                            
                            ForEach(uniqueTypes, id: \.self) { type in
                                Text(badgeText(for: type))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(type.color)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func badgeText(for type: TransitType) -> String {
        switch type {
        case .redLine: return "RL"
        case .orangeLine: return "OL"
        case .greenLine: return "GL"
        case .blueLine: return "BL"
        case .commuterRail: return "CR"
        case .bus: return "Bus"
        case .ferry: return "Ferry"
        case .mattapan: return "Mattapan"
        }
    }
}

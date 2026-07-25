//
//  MotionDashboardView.swift
//  TRoutes
//

import SwiftUI
import ComposableArchitecture

struct MotionDashboardView: View {
    let store: StoreOf<MotionDashboardFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Motion", systemImage: "figure.walk.motion")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(.blue)

                Spacer()
                
                Button {
                    store.send(.toggleListening)
                } label: {
                    Text(store.isListening ? "Stop" : "Start")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(store.isListening ? .red : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(store.isListening ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                debugSection(
                    "Activity",
                    rows: [
                        ("State", store.currentActivity),
                        ("Confidence", store.confidence)
                    ]
                )
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.blue.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal)
    }

    private func debugSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)

                    Text(value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

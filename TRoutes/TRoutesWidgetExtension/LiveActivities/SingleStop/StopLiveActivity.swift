//
//  StopLiveActivity.swift
//  TRoutes
//
//  Created by Adam Post on 8/23/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct StopLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: StopActivityAttributes.self) { context in
			StopLockScreenView(context: context)
				.activityBackgroundTint(.clear)
		} dynamicIsland: { context in
			DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					routeBadge(context.attributes)
				}
				DynamicIslandExpandedRegion(.center) {
					VStack(alignment: .leading, spacing: 2) {
						Text(context.attributes.stopName)
							.font(.headline)
							.lineLimit(1)
						Text("To \(context.attributes.destination)")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				DynamicIslandExpandedRegion(.bottom) {
					predictionRow(context.state.predictions, attributes: context.attributes)
				}
			} compactLeading: {
				Text(context.attributes.routeBadge)
					.font(.caption.bold())
					.foregroundStyle(Color(hex: context.attributes.colorHex))
			} compactTrailing: {
				Text(compactTime(context.state.predictions.first))
			} minimal: {
				Text(context.attributes.routeBadge)
					.font(.caption.bold())
					.foregroundStyle(Color(hex: context.attributes.colorHex))
			}
		}
	}

	private func routeBadge(_ attributes: StopActivityAttributes) -> some View {
		Text(attributes.routeBadge)
			.font(.caption.bold())
			.foregroundStyle(Color(hex: attributes.foregroundColorHex))
			.padding(.horizontal, 7)
			.padding(.vertical, 4)
			.background(Color(hex: attributes.colorHex))
			.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
	}

	private func predictionRow(_ predictions: [String], attributes: StopActivityAttributes) -> some View {
		HStack(spacing: 8) {
			if predictions.isEmpty {
				Text("No upcoming departures")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(Array(predictions.prefix(3).enumerated()), id: \.offset) { _, prediction in
					Text(prediction)
						.font(.subheadline.bold())
						.lineLimit(1)
						.minimumScaleFactor(0.7)
						.foregroundStyle(Color(hex: attributes.foregroundColorHex))
						.padding(.horizontal, 9)
						.frame(minHeight: 30)
						.background(Color(hex: attributes.colorHex))
						.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
				}
			}
		}
	}

	private func compactTime(_ time: String?) -> String {
		guard let time else { return "--" }
		switch time.lowercased() {
		case "arriving": return "ARR"
		case "boarding": return "BRD"
		default: return time.replacingOccurrences(of: " min", with: "m")
		}
	}
}

private struct StopLockScreenView: View {
	let context: ActivityViewContext<StopActivityAttributes>

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .top, spacing: 10) {
				Text(context.attributes.routeBadge)
					.font(.caption.bold())
					.foregroundStyle(Color(hex: context.attributes.foregroundColorHex))
					.padding(.horizontal, 7)
					.padding(.vertical, 4)
					.background(Color(hex: context.attributes.colorHex))
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

				VStack(alignment: .leading, spacing: 2) {
					Text(context.attributes.stopName)
						.font(.headline)
						.lineLimit(2)
					if let routeDetail = context.attributes.routeDetail {
						Text(routeDetail)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Label(context.attributes.destination, systemImage: "arrow.right")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			HStack(spacing: 8) {
				if context.state.predictions.isEmpty {
					Text("No upcoming departures")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				} else {
					ForEach(Array(context.state.predictions.prefix(3).enumerated()), id: \.offset) { _, prediction in
						Text(prediction)
							.font(.subheadline.bold())
							.lineLimit(1)
							.minimumScaleFactor(0.7)
							.foregroundStyle(Color(hex: context.attributes.foregroundColorHex))
							.padding(.horizontal, 9)
							.frame(minHeight: 30)
							.background(Color(hex: context.attributes.colorHex))
							.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
					}
				}
			}
		}
		.padding(16)
	}
}


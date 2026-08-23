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
			StopLockScreenOrWatchView(context: context)
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
		.supplementalActivityFamilies([.small])
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
				Text("No more departures scheduled today")
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

private struct StopLockScreenOrWatchView: View {
	@Environment(\.activityFamily) private var activityFamily
	let context: ActivityViewContext<StopActivityAttributes>

	var body: some View {
		if activityFamily == .small {
			StopWatchView(context: context)
		} else {
			StopLockScreenView(context: context)
		}
	}
}

private struct StopWatchView: View {
	let context: ActivityViewContext<StopActivityAttributes>

	var body: some View {
		HStack(spacing: 8) {
			Text(context.attributes.routeBadge)
				.font(.headline.bold())
				.lineLimit(1)
				.minimumScaleFactor(0.5)
				.foregroundStyle(Color(hex: context.attributes.foregroundColorHex))
				.frame(minWidth: 36, minHeight: 32)
				.padding(.horizontal, 6)
				.background(Color(hex: context.attributes.colorHex).gradient.opacity(0.8))
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

			if let prediction = context.state.predictions.first {
				Text(prediction)
					.font(.subheadline.bold())
					.lineLimit(1)
					.minimumScaleFactor(0.6)
					.frame(maxWidth: .infinity)
			} else {
				Text(context.attributes.stopName)
					.font(.footnote.weight(.semibold))
					.lineLimit(2)
					.minimumScaleFactor(0.7)
					.frame(maxWidth: .infinity)
			}
		}
		.padding()
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
					Text("No more departures scheduled today")
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
		.frame(maxWidth: .infinity, alignment: .leading)
		.foregroundStyle(.primary)
		.background(.ultraThinMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.stroke(.secondary.opacity(0.2), lineWidth: 1)
		}
		.shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
	}
}


//
//  CourseMateWidgetBundle.swift
//  The widget extension's only entry point: a Live Activity for the newest
//  answer. No home-screen widgets, so the bundle contains just this.
//
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CourseMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        AnswerActivityWidget()
    }
}

struct AnswerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnswerActivityAttributes.self) { context in
            LockScreenAnswer(state: context.state, course: context.attributes.course)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.kindLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(percent(context.state.confidence))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(context.state.needsHuman ? .orange : .secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        if !context.state.headline.isEmpty {
                            Text(context.state.headline)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(context.state.answer)
                            .font(.callout.weight(.medium))
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "text.book.closed")
            } compactTrailing: {
                Text(percent(context.state.confidence))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "text.book.closed")
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct LockScreenAnswer: View {
    let state: AnswerActivityAttributes.ContentState
    let course: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(course.isEmpty ? "CourseMate" : course)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(state.kindLabel.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int((state.confidence * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !state.headline.isEmpty {
                Text(state.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(state.answer)
                .font(.callout.weight(.medium))
                .lineLimit(4)

            HStack(spacing: 4) {
                if state.needsHuman {
                    Text("check this one")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(state.updated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }
}

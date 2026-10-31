//
//  CourseMateWidgetBundle.swift
//  The widget extension's only entry point: a Live Activity for the newest
//  answer. No home-screen widgets, so the bundle contains just this.
//
//  Both surfaces carry the same two buttons. They are the reason this is nicer
//  than a notification: the answer can be copied or dismissed without opening
//  anything.
//
import ActivityKit
import AppIntents
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
                .widgetURL(decisionURL(context.state.decisionId))
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
                    VStack(alignment: .leading, spacing: 4) {
                        if !context.state.headline.isEmpty {
                            Text(context.state.headline)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(context.state.answer)
                            .font(.callout.weight(.medium))
                            .lineLimit(3)

                        AnswerButtons(compact: true)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The buttons above still win: a tap on Copy or End runs its
                    // intent, and everything else opens the answer.
                    .widgetURL(decisionURL(context.state.decisionId))
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

    /// `coursemate://decision/<id>`, built from components so an id is escaped
    /// rather than pasted into a string. An empty id yields nil, which leaves a
    /// card with no decision un-tappable instead of opening the app to nothing.
    private func decisionURL(_ id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "coursemate"
        components.host = "decision"
        components.path = "/" + id
        return components.url
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// Copy and End, shared by both surfaces so they cannot drift apart.
private struct AnswerButtons: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CopyAnswerIntent()) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(compact ? .caption2 : .caption)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(intent: EndAnswerIntent()) {
                Label("End", systemImage: "xmark")
                    .font(compact ? .caption2 : .caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
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

            AnswerButtons()
        }
        .padding(12)
    }
}

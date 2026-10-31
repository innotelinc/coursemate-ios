//
//  AnswerActivityAttributes.swift
//  Shared by the app (which starts and updates the activity) and the widget
//  extension (which draws it).
//
//  A Live Activity is the only way to put an answer on screen over another app
//  without the user pulling down a notification — it renders in the Dynamic
//  Island and on the Lock Screen while the course app stays in front.
//
//  The card's two buttons live here too, next to the attributes, because this is
//  the one file both targets already compile: the widget needs the intent types
//  to draw the buttons, and `LiveActivityIntent` makes the system run the body
//  in the app's process, where the pasteboard lives.
//
import ActivityKit
import AppIntents
import Foundation
import UIKit

struct AnswerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// What a tap on the card opens. Carried in the state rather than the
        /// attributes because the card can be updated for a newer decision
        /// without starting a new activity.
        var decisionId: String
        var kindLabel: String
        var confidence: Double
        var headline: String
        var answer: String
        var needsHuman: Bool
        var updated: Date
    }

    /// Fixed for the lifetime of one activity.
    var course: String
}

// MARK: - Card buttons

/// Neither button opens the app: tapping one on the Lock Screen should not pull
/// you out of the lecture, so the work happens in the background.
struct CopyAnswerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Copy answer"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // One activity exists per session by design, so "first" is the card
        // currently on screen.
        guard let activity = Activity<AnswerActivityAttributes>.activities.first else {
            return .result()
        }
        let answer = activity.content.state.answer
        guard !answer.isEmpty else { return .result() }
        UIPasteboard.general.string = answer
        return .result()
    }
}

struct EndAnswerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End answer"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // Dismissing means gone now, not "gone after it lingers on the Lock
        // Screen" — the user asked for it to go away.
        for activity in Activity<AnswerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

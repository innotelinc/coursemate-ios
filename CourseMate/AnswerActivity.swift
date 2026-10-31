//
//  AnswerActivity.swift
//
//  Starts and updates the Live Activity. This is the one channel that puts a new
//  answer in front of the user while they are still in the course app: it
//  renders in the Dynamic Island and on the Lock Screen, and unlike a
//  notification it stays there until replaced.
//
//  One activity per session, reused and updated, so a lecture does not stack up
//  a dozen cards in the Dynamic Island.
//
import ActivityKit
import Foundation

final class AnswerActivity {
    static let shared = AnswerActivity()

    private var current: Activity<AnswerActivityAttributes>?

    /// Whether the system allows Live Activities at all (Settings, or the
    /// per-app switch). Asking each time avoids caching a stale answer.
    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func show(_ decision: CMDecision, course: String) {
        guard isEnabled else { return }

        let state = AnswerActivityAttributes.ContentState(
            decisionId: decision.id,
            kindLabel: decision.kindLabel,
            confidence: decision.confidence,
            headline: decision.headline,
            answer: decision.answer,
            needsHuman: decision.needsHuman,
            updated: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(600)
        )

        // Two ways `current` disagrees with what is on screen. The card's End
        // button runs in this process, so `current` can point at a finished
        // activity (updating that returns false and leaves nothing visible).
        // And a Live Activity outlives the process, so after a relaunch
        // `current` is nil while a card is still up — asking for a new one
        // would stack a second card next to it. Adopt the live one instead.
        let live = current ?? Activity<AnswerActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }

        if let live {
            current = live
            Task { _ = await live.update(content) }
            return
        }

        current = nil
        do {
            current = try Activity.request(
                attributes: AnswerActivityAttributes(course: course),
                content: content,
                pushType: nil
            )
        } catch {
            NSLog("CourseMate: Live Activity not started: \(error.localizedDescription)")
        }
    }

    /// Ends the card with the last state left on screen briefly, then removes it.
    func clear() {
        guard let current else { return }
        self.current = nil
        Task { await current.end(nil, dismissalPolicy: .default) }
    }
}

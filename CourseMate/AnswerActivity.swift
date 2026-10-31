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

        // The card's own End button runs in this process too, so `current` can
        // point at an activity that is already finished. Updating that returns
        // false and leaves nothing on screen, so a dead card is replaced instead
        // of being updated forever.
        if let current, current.activityState == .active || current.activityState == .stale {
            Task { _ = await current.update(content) }
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

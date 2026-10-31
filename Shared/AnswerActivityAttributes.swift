//
//  AnswerActivityAttributes.swift
//  Shared by the app (which starts and updates the activity) and the widget
//  extension (which draws it).
//
//  A Live Activity is the only way to put an answer on screen over another app
//  without the user pulling down a notification — it renders in the Dynamic
//  Island and on the Lock Screen while the course app stays in front.
//
import ActivityKit
import Foundation

struct AnswerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
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

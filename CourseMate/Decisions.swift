//
//  Decisions.swift
//
//  What the server decided about each screen, in the app rather than only in the
//  browser dashboard: a ReplayKit broadcast keeps running while you are in the
//  course, so swiping back to CourseMate is how you read an answer mid-lecture.
//
//  The rows come from `GET /api/desk`, whose payload is a per-kind dictionary
//  (quiz_answer / essay / lecture_notes / error). It is decoded defensively:
//  an unknown kind still renders its kind and confidence instead of vanishing.
//
import SwiftUI
import UIKit

struct CMDecision: Identifiable, Equatable {
    let id: String
    let kind: String
    let screenType: String
    let ts: Date
    let confidence: Double
    let needsHuman: Bool

    /// The question, or the first line of whatever the model produced.
    let headline: String
    /// The answer to actually give: chosen option, answer text, prose, notes.
    let answer: String
    let work: String
    let evidence: String
    let options: [String]
    let chosenIndex: Int?

    var confidenceLabel: String { String(format: "%.0f%%", confidence * 100) }

    var kindLabel: String {
        switch kind {
        case "quiz_answer": return "Quiz"
        case "essay": return "Essay"
        case "lecture_notes": return "Notes"
        case "observation": return "Screen"
        case "error": return "Error"
        default: return kind
        }
    }

    /// Falls back to the most specific field present, so a row is never blank.
    var summary: String {
        let first = answer.isEmpty ? headline : answer
        return first.split(separator: "\n").first.map(String.init) ?? ""
    }
}

enum DecisionDecoder {
    static func from(_ row: [String: Any]) -> CMDecision? {
        guard let id = row["id"] as? String else { return nil }
        let payload = row["payload"] as? [String: Any] ?? [:]

        // `question` is a string for free response and an object carrying the
        // visible options for multiple choice, so both shapes are accepted.
        var questionText = ""
        var options: [String] = []
        if let raw = payload["question"] {
            switch raw {
            case let text as String:
                questionText = text
            case let object as [String: Any]:
                // The server's question object is {stem, kind, options} — see
                // normaliseQuestion() in brain.js. "text" and "prompt" are kept
                // only because an older payload shape used them.
                questionText = (object["stem"] as? String)
                    ?? (object["text"] as? String)
                    ?? (object["prompt"] as? String)
                    ?? ""
                options = object["options"] as? [String] ?? []
            default:
                break
            }
        }
        if options.isEmpty, let list = payload["options"] as? [String] { options = list }

        let chosen = payload["chosen_text"] as? String
        let answerText = (payload["answer_text"] as? String) ?? ""
        let prose = (payload["prose"] as? String) ?? ""
        let notes = (payload["notes"] as? String) ?? (payload["note"] as? String) ?? ""
        let error = (payload["error"] as? String) ?? ""

        let answer = [chosen, answerText, prose, notes]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? ""

        let headline = [questionText, (payload["topic"] as? String) ?? "", error, (row["kind"] as? String) ?? ""]
            .first { !$0.isEmpty } ?? ""

        let needsHuman = (row["needs_human"] as? Bool)
            ?? ((row["needs_human"] as? Int).map { $0 != 0 })
            ?? ((row["needs_human"] as? NSNumber)?.boolValue)
            ?? false

        let seconds = (row["ts"] as? Double) ?? (row["ts"] as? NSNumber)?.doubleValue ?? 0

        return CMDecision(
            id: id,
            kind: (row["kind"] as? String) ?? "unknown",
            screenType: (row["screen_type"] as? String) ?? "",
            ts: Date(timeIntervalSince1970: seconds),
            confidence: (row["confidence"] as? Double)
                ?? (row["confidence"] as? NSNumber)?.doubleValue ?? 0,
            needsHuman: needsHuman,
            headline: headline,
            answer: answer,
            work: (payload["work"] as? String) ?? "",
            evidence: (payload["evidence"] as? String) ?? "",
            options: options,
            chosenIndex: (payload["chosen_index"] as? Int)
                ?? (payload["chosen_index"] as? NSNumber)?.intValue
        )
    }
}

// MARK: - Fetching

// App target only: this file is where CMDecision lives, and the extension does
// not need the desk at all, so it stays out of the shared API surface.
extension CourseMateAPI {
    /// Recent decisions for one session, newest first.
    static func desk(
        base: String,
        token: String,
        session: String,
        limit: Int = 20
    ) async throws -> [CMDecision] {
        let encoded = session.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session
        let data = try await get(base: base, token: token, path: "/api/desk?session_id=\(encoded)&limit=\(limit)")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = object?["decisions"] as? [[String: Any]] ?? []
        return rows.compactMap(DecisionDecoder.from)
    }

    /// Feeds the correction loop: a wrong answer with the right one attached
    /// becomes a lesson immediately, without waiting for a reflection pass.
    static func correct(
        base: String,
        token: String,
        decisionID: String,
        correct: Bool,
        truth: String
    ) async throws {
        _ = try await post(
            base: base,
            token: token,
            path: "/api/correct",
            payload: [
                "decision_id": decisionID,
                "correct": correct,
                "truth": truth,
            ]
        )
    }
}

// MARK: - Row

struct DecisionRow: View {
    let decision: CMDecision
    var graded: Bool? = nil
    var grading: Bool = false
    var onGrade: ((Bool, String) -> Void)? = nil

    @State private var copied = false
    @State private var askingTruth = false
    @State private var truth = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(decision.kindLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())

                Text(decision.confidenceLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(decision.confidence < 0.5 ? .orange : .secondary)

                if decision.needsHuman {
                    Label("review", systemImage: "person.fill.questionmark")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(decision.ts, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !decision.headline.isEmpty {
                Text(decision.headline)
                    .font(.callout)
                    .lineLimit(2)
            }

            if !decision.answer.isEmpty {
                Text(decision.answer)
                    .font(.callout.weight(.medium))
                    .lineLimit(decision.kind == "essay" ? 3 : 4)
                    .textSelection(.enabled)
            }

            if !decision.options.isEmpty, let chosen = decision.chosenIndex, decision.options.indices.contains(chosen) {
                HStack(spacing: 4) {
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                index == chosen
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                }
            }

            HStack(spacing: 10) {
                if !decision.answer.isEmpty {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = decision.answer
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                if onGrade != nil {
                    if let graded {
                        Label(
                            graded ? "marked right" : "marked wrong",
                            systemImage: graded ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(graded ? Color.green : Color.orange)
                    } else if grading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button {
                            onGrade?(true, "")
                        } label: {
                            Label("Right", systemImage: "checkmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            askingTruth = true
                        } label: {
                            Label("Wrong", systemImage: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .tint(.orange)
                    }
                }

                if !decision.evidence.isEmpty {
                    Text(decision.evidence).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .alert("What was the right answer?", isPresented: $askingTruth) {
            TextField("e.g. 42 kJ/mol", text: $truth)
            Button("Send") {
                onGrade?(false, truth)
                truth = ""
            }
            Button("Cancel", role: .cancel) { truth = "" }
        } message: {
            Text("It becomes a lesson the agent applies on later screens. Leaving it blank still records the correction.")
        }
    }
}

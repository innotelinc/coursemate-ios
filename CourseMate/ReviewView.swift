//
//  ReviewView.swift
//
//  A session, afterwards. `/api/me` supplies the recent sessions, what the agent
//  has learned for this course, and its per-screen-type accuracy; `/api/desk`
//  supplies one session's decisions, which include the lecture notes it took.
//
//  Grading works here too, so a bad answer found during review still becomes a
//  lesson rather than just an observation.
//
import SwiftUI

// MARK: - Models

struct CMSessionRow: Identifiable, Equatable {
    let id: String
    let course: String
    let startedAt: Date?
}

struct CMLesson: Identifiable, Equatable {
    let id: String
    let text: String
    let scope: String
    let weight: Double
}

struct CMTrackRecord: Identifiable, Equatable {
    let screenType: String
    let graded: Int
    let accuracy: Double

    var id: String { screenType }
}

struct CMReview: Equatable {
    var sessions: [CMSessionRow] = []
    var lessons: [CMLesson] = []
    var stats: [CMTrackRecord] = []
}

// MARK: - Decoding

enum ReviewDecoder {
    /// The server stores timestamps as ISO strings; a number is accepted too so
    /// a schema change degrades to "no date" rather than an empty screen.
    static func date(_ value: Any?) -> Date? {
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    static func review(from object: [String: Any]) -> CMReview {
        var review = CMReview()

        let sessionRows = object["sessions"] as? [[String: Any]] ?? []
        review.sessions = sessionRows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return CMSessionRow(
                id: id,
                course: (row["course"] as? String) ?? "",
                startedAt: date(row["started_at"] ?? row["startedAt"] ?? row["created_at"])
            )
        }

        let lessonRows = object["lessons"] as? [[String: Any]] ?? []
        review.lessons = lessonRows.compactMap { row in
            guard let text = row["text"] as? String, !text.isEmpty else { return nil }
            let id = (row["id"] as? NSNumber)?.stringValue
                ?? (row["id"] as? String)
                ?? String(text.prefix(40))
            return CMLesson(
                id: id,
                text: text,
                scope: (row["scope"] as? String) ?? "",
                weight: (row["weight"] as? NSNumber)?.doubleValue ?? 0
            )
        }

        let statRows = object["stats"] as? [[String: Any]] ?? []
        review.stats = statRows.compactMap { row in
            guard let type = row["screen_type"] as? String else { return nil }
            let graded = (row["graded"] as? NSNumber)?.intValue ?? 0
            guard graded > 0 else { return nil }
            return CMTrackRecord(
                screenType: type,
                graded: graded,
                accuracy: (row["accuracy"] as? NSNumber)?.doubleValue ?? 0
            )
        }

        return review
    }
}

extension CourseMateAPI {
    static func review(base: String, token: String, course: String) async throws -> CMReview {
        let encoded = course.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await get(base: base, token: token, path: "/api/me?course=\(encoded)")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return ReviewDecoder.review(from: object)
    }

    static func decisions(base: String, token: String, session: String, limit: Int) async throws -> [CMDecision] {
        let encoded = session.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session
        let data = try await get(base: base, token: token, path: "/api/desk?session_id=\(encoded)&limit=\(limit)")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = object?["decisions"] as? [[String: Any]] ?? []
        return rows.compactMap(DecisionDecoder.from)
    }
}

// MARK: - Screen

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var review = CMReview()
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Form {
            if loading {
                Section { HStack { ProgressView(); Text("Loading…").font(.footnote) } }
            }

            if let error {
                Section("Server") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            sessionsSection
            lessonsSection
            trackRecordSection
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var sessionsSection: some View {
        Section {
            if review.sessions.isEmpty && !loading {
                Text("No sessions yet. Start one from the main screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(review.sessions) { session in
                NavigationLink {
                    SessionReviewView(session: session)
                        .environmentObject(model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.course.isEmpty ? "Untitled course" : session.course)
                            .font(.callout)
                        HStack(spacing: 6) {
                            Text(session.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if let started = session.startedAt {
                                Text(started.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if session.id == model.sessionID {
                                Text("live")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("Each row opens that session's decisions and the notes taken during it.")
        }
    }

    private var lessonsSection: some View {
        Section {
            if review.lessons.isEmpty {
                Text("Nothing learned for this course yet. Grade an answer to create a lesson.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(review.lessons) { lesson in
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.text)
                        .font(.footnote)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(lesson.scope)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        Text(String(format: "weight %.2f", lesson.weight))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("What it learned")
        }
    }

    private var trackRecordSection: some View {
        Section {
            if review.stats.isEmpty {
                Text("No graded answers yet — accuracy appears after a few corrections.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(review.stats) { record in
                LabeledContent(record.screenType) {
                    Text(String(format: "%.0f%% · %d graded", record.accuracy * 100, record.graded))
                        .font(.footnote.monospacedDigit())
                }
            }
        } header: {
            Text("Track record")
        } footer: {
            Text("How often a correction agreed, per screen type. Low numbers mean be more careful there.")
        }
    }

    private func load() async {
        let base = model.server
        let bearer = model.token
        let course = model.course.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run { loading = true }
        do {
            let result = try await CourseMateAPI.review(base: base, token: bearer, course: course)
            await MainActor.run {
                review = result
                error = nil
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }
}

// MARK: - One session

struct SessionReviewView: View {
    @EnvironmentObject private var model: AppModel
    let session: CMSessionRow

    @State private var decisions: [CMDecision] = []
    @State private var loading = true
    @State private var error: String?

    private var answers: [CMDecision] { decisions.filter { $0.kind == "quiz_answer" || $0.kind == "essay" } }
    private var notes: [CMDecision] { decisions.filter { $0.kind == "lecture_notes" } }
    private var others: [CMDecision] {
        decisions.filter { $0.kind != "quiz_answer" && $0.kind != "essay" && $0.kind != "lecture_notes" }
    }

    var body: some View {
        Form {
            if loading && decisions.isEmpty {
                Section { HStack { ProgressView(); Text("Loading…").font(.footnote) } }
            }
            if let error {
                Section("Server") {
                    Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                }
            }

            row(answers, title: "Answers")
            row(notes, title: "Notes")
            row(others, title: "Other")

            if !loading && decisions.isEmpty && error == nil {
                Section {
                    Text("No decisions recorded in this session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(session.course.isEmpty ? "Session" : session.course)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ items: [CMDecision], title: String) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { decision in
                    DecisionRow(
                        decision: decision,
                        graded: model.graded[decision.id],
                        grading: model.grading.contains(decision.id),
                        onGrade: { correct, truth in
                            model.grade(decision, correct: correct, truth: truth)
                        }
                    )
                }
            } header: {
                Text("\(title) · \(items.count)")
            }
        }
    }

    private func load() async {
        let base = model.server
        let bearer = model.token
        let id = session.id
        await MainActor.run { loading = true }
        do {
            let list = try await CourseMateAPI.decisions(base: base, token: bearer, session: id, limit: 200)
            await MainActor.run {
                decisions = list
                error = nil
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }
}

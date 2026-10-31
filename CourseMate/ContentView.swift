//
//  ContentView.swift
//
//  The app itself does not capture anything. It exists to (a) create a session
//  the extension can post into and (b) start the system broadcast, because a
//  background app cannot see another app's screen — only a ReplayKit
//  broadcast extension can.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var launcher: BroadcastLauncher
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Form {
                sessionSection
                broadcastSection
                deskSection
                reviewSection
                serverSection

                if let notice = model.notice {
                    Section {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("CourseMate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gear") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(model)
            }
            // Restarts when the session changes, and stops when the view does;
            // the broadcast itself keeps running either way.
            .task(id: model.sessionID) {
                while !Task.isCancelled {
                    await model.refresh()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    private var sessionSection: some View {
        Section {
            TextField("Course name", text: $model.course)
                .textInputAutocapitalization(.words)

            if model.sessionID.isEmpty {
                Text("No session yet — the extension needs one before it can send frames.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Session") {
                    Text(model.sessionID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }

            Button {
                model.createSession()
            } label: {
                if model.busy {
                    ProgressView()
                } else {
                    Text(model.sessionID.isEmpty ? "Start new session" : "Replace session")
                }
            }
            .disabled(model.busy)
        } header: {
            Text("Course")
        } footer: {
            Text("A session groups observations, transcripts and decisions under one course.")
        }
    }

    private var broadcastSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(launcher.isBroadcasting ? Color.red : Color.secondary.opacity(0.35))
                    .frame(width: 9, height: 9)
                Text(launcher.isBroadcasting ? "Broadcasting this screen" : "Not broadcasting")
                    .font(.callout)
            }

            if launcher.isBroadcasting {
                Button("Stop broadcast", role: .destructive) { launcher.stop() }
            } else {
                Button("Start broadcast") { launcher.start() }
                    .disabled(model.sessionID.isEmpty)
            }

            if let message = launcher.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Capture")
        } footer: {
            Text("Leave CourseMate, open the course in any app or browser, and the extension keeps sending frames. You can also start it from Control Centre.")
        }
    }

    private var serverSection: some View {
        Section("Server") {
            LabeledContent("Endpoint") {
                Text(model.server)
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button("Test connection") { model.testServer() }
            if let health = model.health {
                Text(health)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let url = model.dashboardURL {
                Link("Open dashboard", destination: url)
            }
        }
    }

    // MARK: - Answers

    private var deskSection: some View {
        Section {
            extensionRow

            Toggle(isOn: Binding(
                get: { model.notifyHighConfidence },
                set: { model.toggleNotifications($0) }
            )) {
                Label("Notify on new answers", systemImage: "bell.badge")
            }

            if let error = model.deskError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if model.decisions.isEmpty {
                Text(
                    model.sessionID.isEmpty
                        ? "Start a session to see what the screen was read as."
                        : "Nothing yet. The first decision appears after the screen changes while broadcasting."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(model.decisions) { decision in
                    DecisionRow(
                        decision: decision,
                        graded: model.graded[decision.id],
                        grading: model.grading.contains(decision.id),
                        onGrade: { correct, truth in
                            model.grade(decision, correct: correct, truth: truth)
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("Answers")
                Spacer()
                if !model.decisions.isEmpty {
                    Text("\(model.decisions.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Newest first, refreshed every few seconds. Right/Wrong is sent to the server as a correction; a wrong answer with the right one attached becomes a lesson. Copy puts the drafted answer on the clipboard.")
        }
    }

    private var reviewSection: some View {
        Section {
            NavigationLink {
                ReviewView()
                    .environmentObject(model)
            } label: {
                Label("Review past sessions", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("Every session's answers and notes, plus what the agent has learned for this course.")
        }
    }

    private var extensionRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.extensionIsFollowing ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(model.extensionIsFollowing ? "Extension is posting to this session" : "Extension not posting to this session")
                    .font(.caption)
            }
            Text(model.extensionSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let last = model.extensionStatus?.last_error, !last.isEmpty {
                Text(last)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

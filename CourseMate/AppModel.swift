//
//  AppModel.swift
//
//  Deliberately not @MainActor: every mutation is funnelled through
//  MainActor.run, which keeps the type usable from plain Swift 5 mode without
//  sending warnings into the build log.
//
import Foundation

final class AppModel: ObservableObject {
    @Published var server: String
    @Published var token: String
    @Published var course: String

    @Published private(set) var sessionID: String
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var health: String?

    /// Newest-first decisions for the current session, and what the extension
    /// says it has actually sent. Both are refreshed by `refresh()`.
    @Published private(set) var decisions: [CMDecision] = []
    @Published private(set) var deskError: String?
    @Published private(set) var extensionStatus: CMStatusPayload?

    /// Every write bumps this so the extension can tell a change from a rewrite.
    private var revision: Int

    init() {
        let stored = CMSettings.load()
        server = stored.server.isEmpty ? "http://127.0.0.1:8790" : stored.server
        token = stored.token
        course = stored.course
        sessionID = stored.sessionID
        revision = CMSettings.currentRevision()
    }

    var settings: CMSettings {
        CMSettings(server: server, token: token, sessionID: sessionID, course: course)
    }

    var dashboardURL: URL? { CMSettings.url(server) }

    var appGroupNote: String {
        AppGroup.isAvailable
            ? "App Group ready — the extension can read this session, and follow changes while it runs."
            : "App Group not provisioned. The extension will fall back to Info.plist values and cannot follow a session switch."
    }

    // MARK: - Broadcast health

    /// True when the extension's last report names the session selected here.
    var extensionIsFollowing: Bool {
        guard let status = extensionStatus, !status.session.isEmpty else { return false }
        return status.session == sessionID
    }

    var extensionSummary: String {
        guard let status = extensionStatus else {
            return "The extension has not reported yet."
        }
        if status.session.isEmpty {
            return "Extension running without a session."
        }
        if status.session != sessionID {
            return "Extension is posting to \(status.session)."
        }
        guard status.last_frame_at > 0 else {
            return "Extension following this session; nothing uploaded yet."
        }
        let age = Date().timeIntervalSince1970 - status.last_frame_at
        return "Last frame \(Self.ageLabel(age)) ago · \(status.frames) frame\(status.frames == 1 ? "" : "s"), \(status.audio_chunks) audio"
    }

    private static func ageLabel(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds / 60))m"
    }

    // MARK: - Actions

    /// Saves for the extension and reports the one failure that is easy to hit:
    /// a free Apple ID, where the container silently does not exist.
    func persist() {
        revision = max(revision, CMSettings.currentRevision()) + 1
        let saved = settings.save(revision: revision)
        notice = saved
            ? nil
            : "Saved in-app only: no App Group container, so the broadcast extension cannot see these values."
        if saved { extensionStatus = ControlChannel.readStatus() }
    }

    func createSession() {
        guard !busy else { return }
        let base = server
        let bearer = token
        let label = course.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        notice = nil

        Task {
            do {
                let id = try await CourseMateAPI.createSession(
                    base: base,
                    token: bearer,
                    course: label.isEmpty ? "Untitled course" : label
                )
                await MainActor.run {
                    self.sessionID = id
                    self.decisions = []
                    self.deskError = nil
                    self.busy = false
                    // Bumps the revision, so a running broadcast moves to the
                    // new session on its next frame instead of needing a restart.
                    self.persist()
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.notice = "Could not create a session: \(error.localizedDescription)"
                }
            }
        }
    }

    func testServer() {
        let base = server
        let bearer = token
        health = "checking…"
        Task {
            do {
                let result = try await CourseMateAPI.health(base: base, token: bearer)
                await MainActor.run { self.health = result }
            } catch {
                await MainActor.run { self.health = error.localizedDescription }
            }
        }
    }

    /// Called on a loop while the view is on screen: extension status is a local
    /// file read, decisions come from the server.
    func refresh() async {
        let status = ControlChannel.readStatus()
        await MainActor.run { self.extensionStatus = status }

        let base = server
        let bearer = token
        let session = sessionID

        guard !session.isEmpty else {
            await MainActor.run {
                self.decisions = []
                self.deskError = nil
            }
            return
        }

        do {
            let list = try await CourseMateAPI.desk(
                base: base,
                token: bearer,
                session: session,
                limit: 20
            )
            await MainActor.run {
                self.decisions = list
                self.deskError = nil
            }
        } catch {
            await MainActor.run { self.deskError = error.localizedDescription }
        }
    }
}

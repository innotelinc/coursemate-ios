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

    /// Decision id → whether a human agreed, and which ones are in flight.
    @Published private(set) var graded: [String: Bool] = [:]
    @Published private(set) var grading: Set<String> = []

    /// Set by a tap on the Live Activity, which opens that answer as a sheet.
    @Published var focusedDecision: CMDecision?

    /// Off until permission is granted; the toggle asks iOS for it.
    @Published private(set) var notifyHighConfidence: Bool

    private static let notifyKey = "cm_notify_high_confidence"

    /// Every write bumps this so the extension can tell a change from a rewrite.
    private var revision: Int

    /// Ids already announced, and the session already primed. Priming is what
    /// stops the first poll from firing twenty notifications for history.
    private var seenDecisionIDs: Set<String> = []
    private var primedSession: String?

    init() {
        let stored = CMSettings.load()
        // A fresh install is already pointed at the hosted server, so the only
        // thing a buyer does is paste a key. A stored plain-HTTP address that is
        // not on the local network is a leftover from before this default, and
        // iOS refuses it under App Transport Security — replacing it turns a
        // mystery error into a connection that works.
        if stored.server.isEmpty {
            server = CMSettings.defaultServer
        } else if stored.server.hasPrefix("http://"), !CMSettings.isLocalHost(stored.server) {
            server = CMSettings.defaultServer
        } else {
            server = stored.server
        }
        token = stored.token
        course = stored.course
        sessionID = stored.sessionID
        revision = CMSettings.currentRevision()
        notifyHighConfidence = UserDefaults.standard.bool(forKey: Self.notifyKey)
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
                    self.primedSession = nil
                    self.seenDecisionIDs = []
                    self.busy = false
                    // The old card belongs to the session it described.
                    AnswerActivity.shared.clear()
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

    /// APNs registration, with the token reported back to the server so it can
    /// push later. Fails harmlessly when the build has no push entitlement.
    func registerPush() {
        PushRegistration.shared.configure(base: CMSettings.normalize(server), token: token)
        PushRegistration.shared.request()
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

    /// Grading a decision feeds `POST /api/correct`; a wrong answer with the
    /// right one attached becomes a lesson immediately.
    func grade(_ decision: CMDecision, correct: Bool, truth: String) {
        guard !grading.contains(decision.id) else { return }
        grading.insert(decision.id)

        let base = server
        let bearer = token
        let id = decision.id

        Task {
            do {
                try await CourseMateAPI.correct(
                    base: base,
                    token: bearer,
                    decisionID: id,
                    correct: correct,
                    truth: truth
                )
                await MainActor.run {
                    self.grading.remove(id)
                    self.graded[id] = correct
                }
            } catch {
                await MainActor.run {
                    self.grading.remove(id)
                    self.notice = "Could not record that: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Asks iOS for permission before turning the toggle on, and turns it back
    /// off if the answer is no — a toggle that stays on while nothing is
    /// delivered would be a lie.
    func toggleNotifications(_ on: Bool) {
        guard on else {
            notifyHighConfidence = false
            return
        }
        AnswerNotifier.shared.requestPermission { [weak self] granted in
            guard let self else { return }
            self.notifyHighConfidence = granted
            UserDefaults.standard.set(granted, forKey: Self.notifyKey)
            if !granted {
                self.notice = "Notifications are not allowed for CourseMate. Enable them in iOS Settings."
            }
        }
    }

    // MARK: - Deep links

    /// A tap on the answer card arrives as `coursemate://decision/<id>`.
    /// Anything else is ignored rather than guessed at.
    func handle(_ url: URL) {
        guard url.scheme == "coursemate", url.host == "decision" else { return }
        let id = url.pathComponents.last ?? ""
        guard !id.isEmpty, id != "/" else { return }
        openDecision(id)
    }

    /// The card can name a decision from before this app opened, or from a
    /// session it no longer has selected, so an id not in `decisions` is fetched
    /// rather than treated as stale.
    func openDecision(_ id: String) {
        if let known = decisions.first(where: { $0.id == id }) {
            focusedDecision = known
            return
        }

        let base = server
        let bearer = token
        Task {
            do {
                let decision = try await CourseMateAPI.decision(base: base, token: bearer, id: id)
                await MainActor.run { self.focusedDecision = decision }
            } catch {
                await MainActor.run {
                    self.notice = "Could not open that answer: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Called on a loop while the view is on screen, and by the background
    /// refresh: extension status is a local file read, decisions come from the
    /// server.
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
                self.announce(list)
            }
        } catch {
            await MainActor.run { self.deskError = error.localizedDescription }
        }
    }

    // MARK: - Notifications

    /// Announces only what is new, only when the answer is worth interrupting
    /// for, and never the backlog that already existed when the app opened.
    private func announce(_ list: [CMDecision]) {
        let session = sessionID

        if primedSession != session {
            primedSession = session
            seenDecisionIDs.formUnion(list.map(\.id))
            return
        }

        guard notifyHighConfidence else {
            seenDecisionIDs.formUnion(list.map(\.id))
            return
        }

        for decision in list.reversed() where !seenDecisionIDs.contains(decision.id) {
            seenDecisionIDs.insert(decision.id)
            guard !decision.needsHuman,
                  decision.confidence >= 0.6,
                  !decision.answer.isEmpty
            else { continue }
            AnswerNotifier.shared.post(decision)
            // The Live Activity is what shows over the course app itself.
            AnswerActivity.shared.show(decision, course: course)
        }
    }
}

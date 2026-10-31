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

    init() {
        let stored = CMSettings.load()
        server = stored.server.isEmpty ? "http://127.0.0.1:8790" : stored.server
        token = stored.token
        course = stored.course
        sessionID = stored.sessionID
    }

    var settings: CMSettings {
        CMSettings(server: server, token: token, sessionID: sessionID, course: course)
    }

    var dashboardURL: URL? { CMSettings.url(server) }

    var appGroupNote: String {
        AppGroup.isAvailable
            ? "App Group ready — the extension can read this session."
            : "App Group not provisioned. The extension will fall back to Info.plist values."
    }

    /// Saves for the extension and reports the one failure that is easy to hit:
    /// a free Apple ID, where the container silently does not exist.
    func persist() {
        let saved = settings.save()
        notice = saved ? nil : "Saved in-app only: no App Group container, so the broadcast extension cannot see these values."
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
                    self.busy = false
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
}

//
//  ControlChannel.swift
//  Shared by the app and the broadcast extension.
//
//  UserDefaults is not a reliable a cross-process bus: writes from the app are
//  not guaranteed to be visible in the extension's process at any particular
//  time. So the app → extension direction is a small JSON file in the App Group
//  container, written atomically (temp file + rename, which a reader can never
//  observe half-finished), and the extension re-reads it only when its
//  modification date changes — a stat call, throttled, not a decode per frame.
//
//  The reverse direction is `status.json`: the extension publishes what it has
//  actually sent, so the app can show "posting to ses_… 2s ago" instead of
//  guessing whether the broadcast is working.
//
import Foundation

// MARK: - Payloads

struct CMControlPayload: Codable, Equatable {
    var server: String
    var token: String
    var session: String
    var course: String
    /// Monotonic; the extension uses it to tell a real switch from a rewrite.
    var revision: Int

    static let empty = CMControlPayload(server: "", token: "", session: "", course: "", revision: 0)
}

struct CMStatusPayload: Codable, Equatable {
    var session: String
    var course: String
    var frames: Int
    var audio_chunks: Int
    var last_frame_at: Double
    var last_audio_at: Double
    var last_error: String
    var revision: Int
    var updated_at: Double

    static let empty = CMStatusPayload(
        session: "", course: "", frames: 0, audio_chunks: 0,
        last_frame_at: 0, last_audio_at: 0, last_error: "",
        revision: 0, updated_at: 0
    )
}

// MARK: - Files

enum ControlChannel {
    static let controlFile = "control.json"
    static let statusFile = "status.json"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    private static func url(_ name: String) -> URL? {
        container?.appendingPathComponent(name)
    }

    static func read<T: Decodable>(_ type: T.Type, file name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, file name: String) -> Bool {
        guard let url = url(name), let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("CourseMate: could not write \(name): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func writeControl(_ payload: CMControlPayload) -> Bool {
        write(payload, file: controlFile)
    }

    static func readControl() -> CMControlPayload? {
        read(CMControlPayload.self, file: controlFile)
    }

    @discardableResult
    static func writeStatus(_ payload: CMStatusPayload) -> Bool {
        write(payload, file: statusFile)
    }

    static func readStatus() -> CMStatusPayload? {
        read(CMStatusPayload.self, file: statusFile)
    }
}

// MARK: - Extension side: follow the control file

/// Answers "has the app changed anything?" cheaply enough to call on every
/// sample buffer. ReplayKit delivers audio far more often than video, so the
/// stat is throttled to twice a second and an unchanged file costs one date
/// comparison.
final class ControlWatcher {
    private let lock = NSLock()
    private var cached: CMControlPayload?
    private var stamp: Date?
    private var lastCheck = Date.distantPast
    private let minInterval: TimeInterval = 0.5

    /// Returns the current payload and whether it differs from the last one
    /// the caller applied, so the caller can reset per-session state.
    func refresh(force: Bool = false) -> (payload: CMControlPayload?, changed: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if !force, now.timeIntervalSince(lastCheck) < minInterval {
            return (cached, false)
        }
        lastCheck = now

        guard let url = ControlChannel.container?.appendingPathComponent(ControlChannel.controlFile) else {
            return (cached, false)
        }

        var modified: Date?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            modified = attributes[.modificationDate] as? Date
        }
        if let modified, modified == stamp {
            return (cached, false)
        }
        stamp = modified

        guard let payload = ControlChannel.readControl() else { return (cached, false) }
        let changed = payload != cached
        cached = payload
        return (payload, changed)
    }
}

// MARK: - Extension side: publish what we sent

/// Counters and the throttled status write. Mutated from the ReplayKit queue
/// and from upload completion tasks, hence the lock.
final class StatusBox {
    private let lock = NSLock()
    private var payload = CMStatusPayload.empty
    private var lastWrite = Date.distantPast
    private let writeInterval: TimeInterval = 2

    func setSession(_ session: String, course: String) {
        lock.lock()
        payload.session = session
        payload.course = course
        lock.unlock()
        flush()
    }

    func recordFrame() {
        lock.lock()
        payload.frames += 1
        payload.last_frame_at = Date().timeIntervalSince1970
        if payload.last_error.hasPrefix("frame") { payload.last_error = "" }
        lock.unlock()
        flush()
    }

    func recordAudio() {
        lock.lock()
        payload.audio_chunks += 1
        payload.last_audio_at = Date().timeIntervalSince1970
        lock.unlock()
        flush()
    }

    func recordError(_ message: String) {
        lock.lock()
        payload.last_error = String(message.prefix(200))
        lock.unlock()
        flush(force: true)
    }

    func flush(force: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) >= writeInterval else { return }
        lastWrite = now
        payload.revision += 1
        payload.updated_at = now.timeIntervalSince1970
        ControlChannel.writeStatus(payload)
    }
}

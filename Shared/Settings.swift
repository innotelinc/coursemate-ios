//
//  Settings.swift
//  Shared by the app and the broadcast extension.
//
//  A ReplayKit broadcast extension runs as its own process and cannot read the
//  app's UserDefaults, so both targets read the same App Group container. The
//  authoritative copy is the control file (see ControlChannel.swift) because
//  the extension has to notice a session switch while it is running; UserDefaults
//  and Info.plist remain as fallbacks so it is never silently unconfigured.
//
import Foundation

enum CMKey {
    static let server = "cm_url"
    static let token = "cm_token"
    static let session = "cm_session"
    static let course = "cm_course"
}

enum AppGroup {
    static let identifier = "group.us.innotel.coursemate"

    /// nil when the entitlement is not provisioned or the container is missing.
    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }

    static var isAvailable: Bool { defaults != nil }

    /// App Group value first, then the same key from this bundle's Info.plist.
    static func string(_ key: String) -> String? {
        if let value = defaults?.string(forKey: key), !value.isEmpty { return value }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
            return value
        }
        return nil
    }
}

struct CMSettings: Equatable {
    var server: String
    var token: String
    var sessionID: String
    var course: String

    static let empty = CMSettings(server: "", token: "", sessionID: "", course: "")

    /// The hosted server. A fresh install needs no setup at all: this is the
    /// endpoint, and buying a key is the only thing left to do.
    static let defaultServer = "https://cm.innotel.us"

    static func load() -> CMSettings {
        let control = ControlChannel.readControl()

        func pick(_ preferred: String?, _ key: String) -> String {
            if let preferred, !preferred.isEmpty { return preferred }
            return AppGroup.string(key) ?? ""
        }

        return CMSettings(
            server: pick(control?.server, CMKey.server),
            // A cleared token is meaningful, so only fall back when there is no
            // control file at all rather than when the field is empty.
            token: control.map(\.token) ?? AppGroup.string(CMKey.token) ?? "",
            sessionID: pick(control?.session, CMKey.session),
            course: pick(control?.course, CMKey.course)
        )
    }

    /// The revision the extension last saw; the app only needs to beat it.
    static func currentRevision() -> Int {
        ControlChannel.readControl()?.revision ?? 0
    }

    /// Writes through to the App Group when it exists; returns whether anything
    /// was persisted, so the UI can say "this will not reach the extension"
    /// instead of assuming success. The revision must increase for the
    /// extension to treat this as a change.
    @discardableResult
    func save(revision: Int) -> Bool {
        guard let defaults = AppGroup.defaults else { return false }

        // Kept for the Control Centre path and for `defaults read` debugging;
        // the extension itself reads the control file.
        defaults.set(Self.normalize(server), forKey: CMKey.server)
        defaults.set(token, forKey: CMKey.token)
        defaults.set(sessionID, forKey: CMKey.session)
        defaults.set(course, forKey: CMKey.course)

        return ControlChannel.writeControl(
            CMControlPayload(
                server: Self.normalize(server),
                token: token,
                session: sessionID,
                course: course,
                revision: revision
            )
        )
    }

    /// Accepts "192.168.1.20:8790", "http://host/" and friends, and always
    /// returns something a URL can be built from.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            // A bare host is the hosted server unless it is clearly a machine on
            // the LAN. Guessing http:// for anything else only produces an ATS
            // error the buyer cannot act on.
            value = (isLocalHost(value) ? "http://" : "https://") + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// True for loopback, `.local`, and the private IPv4 ranges — the addresses a
    /// development server actually listens on.
    static func isLocalHost(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        let host = withoutScheme.split(separator: "/").first.map(String.init) ?? ""
        let name = host.split(separator: ":").first.map(String.init) ?? ""
        if name.isEmpty { return false }
        if name == "localhost" || name.hasSuffix(".local") { return true }
        let parts = name.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false })
        else { return false }
        let a = Int(parts[0]) ?? 0
        let b = Int(parts[1]) ?? 0
        return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b))
    }

    static func url(_ raw: String) -> URL? {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized)
    }
}

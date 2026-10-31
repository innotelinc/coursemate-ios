//
//  Settings.swift
//  Shared by the app and the broadcast extension.
//
//  A ReplayKit broadcast extension runs as its own process and cannot read the
//  app's UserDefaults, so both targets read the same App Group container. When
//  that capability is unavailable (a free Apple ID cannot use App Groups) the
//  extension falls back to Info.plist keys, so it is never silently
//  unconfigured.
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

    static func load() -> CMSettings {
        CMSettings(
            server: AppGroup.string(CMKey.server) ?? "",
            token: AppGroup.string(CMKey.token) ?? "",
            sessionID: AppGroup.string(CMKey.session) ?? "",
            course: AppGroup.string(CMKey.course) ?? ""
        )
    }

    /// Writes through to the App Group when it exists; returns whether anything
    /// was persisted, so the UI can say "this will not reach the extension"
    /// instead of assuming success.
    @discardableResult
    func save() -> Bool {
        guard let defaults = AppGroup.defaults else { return false }
        defaults.set(Self.normalize(server), forKey: CMKey.server)
        defaults.set(token, forKey: CMKey.token)
        defaults.set(sessionID, forKey: CMKey.session)
        defaults.set(course, forKey: CMKey.course)
        return true
    }

    /// Accepts "192.168.1.20:8790", "http://host/" and friends, and always
    /// returns something a URL can be built from.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func url(_ raw: String) -> URL? {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized)
    }
}

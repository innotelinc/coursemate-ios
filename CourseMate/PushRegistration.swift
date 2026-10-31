//
//  PushRegistration.swift
//
//  APNs registration, deliberately without the Push Notifications capability in
//  the entitlements: declaring `aps-environment` forces every signing profile to
//  have push enabled, which breaks installs for anyone who only wants the local
//  notification path. Instead registration is attempted at runtime; if the
//  profile has no push entitlement it fails immediately and the app keeps using
//  local notifications.
//
//  To switch it on: enable the Push Notifications capability for both the app
//  id and the target, then set APNS_* on the server. See README.
//
import UIKit
import UserNotifications

final class PushRegistration: NSObject, ObservableObject {
    static let shared = PushRegistration()
    static let refreshNotification = Notification.Name("cm.push.refresh")

    @Published private(set) var status: String?
    @Published private(set) var deviceToken: String?

    private var base = ""
    private var bearer = ""
    private var lastSentToken = ""

    /// Where to report the token. Called with the app's current settings.
    func configure(base: String, token: String) {
        self.base = base
        self.bearer = token
        if !lastSentToken.isEmpty, lastSentToken == deviceToken {
            send(lastSentToken)
        }
    }

    func request() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token handling

    func registered(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.deviceToken = token
            self.status = "APNs token \(token.prefix(10))…"
        }
        send(token)
    }

    func failed(_ error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            // The common case is "no valid aps-environment entitlement", which
            // is fine: local notifications still work.
            self.status = "Push unavailable (\(message)) — local notifications still work."
        }
    }

    private func send(_ token: String) {
        guard !base.isEmpty else { return }
        lastSentToken = token
        let server = base
        let bearer = self.bearer

        Task {
            do {
                _ = try await CourseMateAPI.post(
                    base: server,
                    token: bearer,
                    path: "/api/devices",
                    payload: [
                        "device_token": token,
                        "platform": "ios",
                        "bundle_id": Bundle.main.bundleIdentifier ?? "",
                    ]
                )
                await MainActor.run { self.status = "Server knows this device." }
            } catch {
                await MainActor.run {
                    self.status = "Token not registered: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// SwiftUI's App lifecycle has no delegate of its own, and APNs callbacks are
/// UIApplicationDelegate methods.
final class CourseMateAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = AnswerNotifier.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistration.shared.registered(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushRegistration.shared.failed(error)
    }

    /// A silent push is only a hint: the server says something changed, the app
    /// then reads the decisions it is allowed to read.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: PushRegistration.refreshNotification, object: nil)
        completionHandler(.newData)
    }
}

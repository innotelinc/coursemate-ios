//
//  AnswerNotifier.swift
//
//  Local notifications for answers worth interrupting for. There is no APNs
//  here, so the honest picture is:
//
//  · Foreground — every new high-confidence decision is announced.
//  · Just after backgrounding — a background task keeps the poll alive briefly.
//  · Later — BGAppRefreshTask, which iOS schedules when it feels like it:
//    minutes, sometimes much longer, and never in Low Power Mode.
//
//  A reliable "ping me 40 minutes into the lecture" needs a push server. That is
//  the only real fix, and it is deliberately not faked here.
//
import BackgroundTasks
import Foundation
import UserNotifications

final class AnswerNotifier: NSObject, ObservableObject {
    static let shared = AnswerNotifier()
    static let refreshIdentifier = "us.innotel.coursemate.refresh"

    /// Set from the view that owns the model; used by the background refresh.
    weak var model: AppModel?

    private var registered = false
    private var lastPosted: Set<String> = []

    /// Call once, before the app finishes launching — BGTaskScheduler requires it.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        guard !registered else { return }
        registered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.run(refresh)
        }
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("CourseMate: notification permission failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    func post(_ decision: CMDecision) {
        guard !lastPosted.contains(decision.id) else { return }
        lastPosted.insert(decision.id)

        let content = UNMutableNotificationContent()
        content.title = "\(decision.kindLabel) · \(decision.confidenceLabel) confidence"
        content.body = decision.summary.isEmpty
            ? "A new screen was read."
            : String(decision.summary.prefix(220))
        content.sound = .default
        content.threadIdentifier = "coursemate-answers"
        content.userInfo = ["decision_id": decision.id]

        let request = UNNotificationRequest(
            identifier: "cm-\(decision.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("CourseMate: notification failed: \(error.localizedDescription)")
            }
        }
    }

    /// Ask iOS for a later wake-up. Best effort by design.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("CourseMate: background refresh not scheduled: \(error.localizedDescription)")
        }
    }

    private func run(_ task: BGAppRefreshTask) {
        schedule() // chain the next opportunity before doing any work

        let work = Task { [weak self] in
            await self?.model?.refresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

extension AnswerNotifier: UNUserNotificationCenterDelegate {
    /// Without this the banner is suppressed whenever the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

//
//  CourseMateApp.swift
//
import SwiftUI

@main
struct CourseMateApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var launcher = BroadcastLauncher()
    @Environment(\.scenePhase) private var scenePhase

    /// APNs callbacks are UIApplicationDelegate methods; SwiftUI has no
    /// equivalent, so one delegate is bridged in for them.
    @UIApplicationDelegateAdaptor(CourseMateAppDelegate.self) private var appDelegate

    init() {
        // BGTaskScheduler requires registration before launch completes, and
        // the notification delegate must be set before any banner arrives.
        AnswerNotifier.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(launcher)
                .onAppear {
                    AnswerNotifier.shared.model = model
                    model.registerPush()
                }
                .onReceive(NotificationCenter.default.publisher(for: PushRegistration.refreshNotification)) { _ in
                    Task { await model.refresh() }
                }
                // Tapping the answer card: the tap is a URL, so it is routed
                // rather than duplicated as a separate presentation path.
                .onOpenURL { model.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // One request per backgrounding; the handler chains the next one.
            if phase == .background { AnswerNotifier.shared.schedule() }
        }
    }
}

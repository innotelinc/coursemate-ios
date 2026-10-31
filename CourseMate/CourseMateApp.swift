//
//  CourseMateApp.swift
//
import SwiftUI

@main
struct CourseMateApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var launcher = BroadcastLauncher()
    @Environment(\.scenePhase) private var scenePhase

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
                .onAppear { AnswerNotifier.shared.model = model }
        }
        .onChange(of: scenePhase) { _, phase in
            // One request per backgrounding; the handler chains the next one.
            if phase == .background { AnswerNotifier.shared.schedule() }
        }
    }
}

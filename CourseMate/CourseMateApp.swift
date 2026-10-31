//
//  CourseMateApp.swift
//
import SwiftUI

@main
struct CourseMateApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var launcher = BroadcastLauncher()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(launcher)
        }
    }
}

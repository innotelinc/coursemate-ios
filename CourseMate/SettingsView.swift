//
//  SettingsView.swift
//
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.20:8790", text: $model.server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Bearer token (optional)", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("The CourseMate server must bind a reachable interface: start it with COURSEMATE_HOST=0.0.0.0. A simulator can use 127.0.0.1; a phone cannot.")
                }

                Section("Course") {
                    TextField("BIOL 201", text: $model.course)
                }

                Section {
                    Button("Test connection") { model.testServer() }
                    if let health = model.health {
                        Text(health)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Connection")
                }

                Section {
                    Text(model.appGroupNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Broadcast extension")
                } footer: {
                    Text("The extension runs in its own process and reads these values from the shared App Group, re-checking while it broadcasts — so a new session takes effect without stopping the broadcast. Without that container it falls back to the cm_url and cm_session keys in its Info.plist and cannot follow changes.")
                }

                Section("How to broadcast") {
                    Label("Start a session above.", systemImage: "1.circle")
                    Label("Tap Start broadcast and wait for the red status bar.", systemImage: "2.circle")
                    Label("Switch to the course — the extension keeps capturing.", systemImage: "3.circle")
                    Label("Or use Control Centre: long-press the record button, choose CourseMate.", systemImage: "4.circle")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.persist()
                        dismiss()
                    }
                }
            }
        }
    }
}

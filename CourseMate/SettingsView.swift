//
//  SettingsView.swift
//
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The server is fixed to the hosted endpoint unless the operator says
    /// otherwise, because "which URL" is not a question a buyer can answer.
    @State private var advanced = false

    var body: some View {
        NavigationStack {
            Form {
                // Its own section, headed in the words people actually use: the
                // value is an API key you buy, and calling it a "bearer token"
                // only made it look like something a developer has to go and
                // find. Nothing about it is an Apple ID or an iCloud password.
                Section {
                    SecureField("Paste your API key", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Link("Buy an API key", destination: Self.buyURL)
                } header: {
                    Text("API key")
                } footer: {
                    Text("The key you bought at cm.innotel.us. It authorises the app and the broadcast extension, so it is the only setup a fresh install needs.")
                }

                Section {
                    LabeledContent("Server", value: model.server)

                    Toggle("Use a different server", isOn: $advanced)

                    if advanced {
                        TextField("https://cm.innotel.us", text: $model.server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("CourseMate runs at cm.innotel.us, so a key is the whole setup. A server on your own network still works — turn on the switch and enter its address, but iOS only permits plain HTTP there, never over the internet.")
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

    /// Where a key is sold. Kept here rather than in the app model because it is
    /// a piece of the settings screen, and it must stay a plain https link: a
    /// deep link into the store would break the day the store's route changes.
    private static let buyURL = URL(string: "https://cm.innotel.us/#price")!
}

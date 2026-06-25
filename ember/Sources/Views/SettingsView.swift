import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SaunaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Address") {
                        TextField("http://your-pi-ip:8765", text: $settings.baseURL)
                            .multilineTextAlignment(.trailing).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().keyboardType(.URL)
                    }
                    LabeledContent("API key") {
                        SecureField("required for control", text: $settings.apiKey)
                            .multilineTextAlignment(.trailing)
                    }
                    Button { test() } label: {
                        HStack { Text("Test connection"); Spacer()
                            if testing { ProgressView() } }
                    }
                    if let r = testResult {
                        Text(r).font(.footnote).foregroundStyle(r.hasPrefix("✓") ? .green : Theme.emberHot)
                    }
                } header: { Text("emberd bridge") } footer: {
                    Text("Reads (temperature) are open; controlling the sauna needs the API key. Reach it away from home via Tailscale.")
                }

                Section("Now") {
                    LabeledContent("Connection", value: store.reachable ? "Connected" : "Offline")
                    if let t = store.state.currentTempF { LabeledContent("Current", value: "\(t)°F") }
                    LabeledContent("Power", value: store.state.power ? "On" : "Off")
                    LabeledContent("Heater", value: store.state.heater ? "On" : "Off")
                }

                Section { LabeledContent("Ember", value: "1.0") }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func test() {
        testing = true; testResult = nil
        Task {
            await store.refresh()
            testing = false
            testResult = store.reachable ? "✓ Connected" : "✗ \(store.lastError ?? "unreachable")"
        }
    }
}

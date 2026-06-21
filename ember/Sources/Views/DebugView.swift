import SwiftUI

/// Temporary DP playground: shows every raw DP live and lets you set anything.
/// Use it to verify mappings (chroma modes, footwell, etc.) by poking + watching.
struct DebugView: View {
    @Environment(AppSettings.self) private var settings
    @State private var raw: [String: String] = [:]
    @State private var online = false
    @State private var dpField = ""
    @State private var valField = ""
    @State private var lastResult = ""
    @State private var pollTask: Task<Void, Never>?

    private var client: EmberClient? {
        guard let url = settings.url else { return nil }
        return EmberClient(base: url, apiKey: settings.apiKey)
    }

    var body: some View {
        List {
            Section("Live DPs  \(online ? "🟢 online" : "🔴 offline")") {
                ForEach(raw.keys.sorted { (Int($0) ?? 9999) < (Int($1) ?? 9999) }, id: \.self) { k in
                    HStack {
                        Text("DP \(k)").font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(raw[k] ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Chroma color (DP 21)") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(0...9, id: \.self) { i in
                        let v = i == 0 ? "mode" : "mode\(i)"
                        Button("m\(i)") { set("21", .str(v)) }.buttonStyle(.bordered)
                    }
                }
            }

            Section("Toggles") {
                toggleRow("Power", "110")
                toggleRow("Heater", "114")
                toggleRow("Footwell", "113")
                toggleRow("Rainbow/cycle", "101")
            }

            Section("Set any DP") {
                TextField("DP # (e.g. 21)", text: $dpField).keyboardType(.numbersAndPunctuation)
                TextField("value", text: $valField)
                HStack {
                    Button("bool T") { set(dpField, .bool(true)) }
                    Button("bool F") { set(dpField, .bool(false)) }
                    Button("int") { if let n = Int(valField) { set(dpField, .int(n)) } }
                    Button("str") { set(dpField, .str(valField)) }
                }.buttonStyle(.bordered)
            }

            if !lastResult.isEmpty {
                Section("Last") { Text(lastResult).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Debug DPs")
        .onAppear { startPoll() }
        .onDisappear { pollTask?.cancel() }
    }

    private func toggleRow(_ name: String, _ dp: String) -> some View {
        HStack {
            Text("\(name) (DP \(dp))")
            Spacer()
            Button("ON") { set(dp, .bool(true)) }.buttonStyle(.bordered).tint(.green)
            Button("OFF") { set(dp, .bool(false)) }.buttonStyle(.bordered).tint(.red)
        }
    }

    private func set(_ dp: String, _ value: DebugValue) {
        guard let client, !dp.isEmpty else { return }
        Haptics.tap()
        Task {
            do {
                try await client.debugSet(dp: dp, value: value)
                lastResult = "set DP \(dp) ✓"
                await refresh()
            } catch {
                lastResult = "DP \(dp): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            }
        }
    }

    private func refresh() async {
        guard let client else { return }
        if let r = try? await client.debugRaw() { raw = r.raw; online = r.online }
    }

    private func startPoll() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

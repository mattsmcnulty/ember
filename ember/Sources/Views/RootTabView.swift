import SwiftUI

struct RootTabView: View {
    @Environment(SaunaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        TabView {
            controlTab.tabItem { Label("Control", systemImage: "flame.fill") }
            logTab.tabItem { Label("Log", systemImage: "list.bullet.rectangle.portrait") }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { store.startPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.startPolling() } else { store.stopPolling() }
        }
    }

    private var controlTab: some View {
        NavigationStack {
            ControlView()
                .background(Theme.background)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsButton }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var logTab: some View {
        NavigationStack {
            LogView()
                .background(Theme.background)
                .navigationTitle("Log")
                .toolbar { settingsButton }
        }
    }

    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .tint(Theme.textSecondary)
        }
    }
}

import SwiftUI

struct RootTabView: View {
    @Environment(SaunaStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        TabView {
            controlTab.tabItem { Label("Control", systemImage: "flame.fill") }
            logTab.tabItem { Label("Log", systemImage: "list.bullet.rectangle.portrait") }
            #if DEBUG
            debugTab.tabItem { Label("Debug", systemImage: "ladybug.fill") }
            #endif
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { SaunaActivityController.shared.configure(settings); store.startPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.startPolling() } else { store.stopPolling() }
        }
    }

    private var controlTab: some View {
        NavigationStack {
            ControlView()
                .background(Theme.background)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsButton; powerButton }
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

    #if DEBUG
    private var debugTab: some View {
        NavigationStack { DebugView().background(Theme.background) }
    }
    #endif

    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .tint(Theme.textSecondary)
        }
    }

    @ToolbarContentBuilder private var powerButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Task { await store.setPower(!store.state.power) } } label: {
                Image(systemName: "power")
            }
            .tint(store.state.power ? Theme.ember : Theme.textSecondary)
        }
    }
}

import SwiftData
import SwiftUI

@main
struct emberApp: App {
    @State private var settings: AppSettings
    @State private var store: SaunaStore

    init() {
        let s = AppSettings()
        _settings = State(initialValue: s)
        _store = State(initialValue: SaunaStore(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(settings)
                .environment(store)
                .tint(Theme.ember)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: SaunaSession.self)
    }
}

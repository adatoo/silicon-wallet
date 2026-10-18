import SwiftUI

@main
struct SiliconWalletApp: App {
    @State private var model: AppModel
    @State private var lock: LockController

    init() {
        let model = AppModel.launch()
        _model = State(initialValue: model)
        _lock = State(initialValue: LockController(model: model))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .onAppear { lock.start() }
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 700)
        #endif
        .commands {
            VaultCommands(model: model, lock: lock)
        }

        #if os(macOS)
            Settings {
                SettingsView()
                    .environment(model)
                    .environment(lock)
            }
        #endif
    }
}

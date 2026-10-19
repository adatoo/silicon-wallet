import SwiftUI

@main
struct SiliconWalletApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(PushRegistration.self) private var push
    #else
        @NSApplicationDelegateAdaptor(PushRegistration.self) private var push
    #endif
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
                .onAppear {
                    lock.start()
                    model.sync?.start()
                }
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

            Window("Silicon Wallet Help", id: HelpView.windowID) {
                HelpView()
            }
            .defaultSize(width: 780, height: 540)
        #endif
    }
}

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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel.launch()
        _model = State(initialValue: model)
        _lock = State(initialValue: LockController(model: model))
    }

    /// Opens the vault once the device has been unlocked, if the app was woken in the background
    /// before that (`AppModel.isWaitingForDeviceUnlock`).
    private func relaunchIfWaiting() {
        guard model.isWaitingForDeviceUnlock else { return }
        let relaunched = AppModel.launch()
        guard !relaunched.isWaitingForDeviceUnlock else { return }
        model = relaunched
        lock = LockController(model: relaunched)
        lock.start()
        relaunched.sync?.start()
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
                #if os(iOS)
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.protectedDataDidBecomeAvailableNotification)
                    ) { _ in
                        relaunchIfWaiting()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { relaunchIfWaiting() }
                    }
                #endif
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

import SiliconWalletKit
import SwiftUI

/// Chooses the screen for the vault's state: first-run setup, unlock, or the vault itself.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if let session = model.session {
                switch session.state {
                case .noVault: SetupView()
                case .locked: UnlockView()
                case .unlocked: VaultView()
                }
            } else if model.isWaitingForDeviceUnlock {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Silicon Wallet Can't Open Its Vault", systemImage: "exclamationmark.lock",
                    description: Text(model.startupError ?? "Unknown error."))
            }
        }
        #if os(iOS)
            .background(ActivityRecognizerInstaller { lock.recordActivity() })
            .overlay {
                if scenePhase != .active { PrivacyCover() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: lock.didEnterBackground()
                case .active: lock.didBecomeActive()
                default: break
                }
            }
        #endif
        .task { await model.prepareDemoIfRequested() }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

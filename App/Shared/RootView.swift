import SiliconWalletKit
import SwiftUI

/// Chooses the screen for the vault's state: first-run setup, unlock, or the vault itself.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let session = model.session {
                switch session.state {
                case .noVault: SetupView()
                case .locked: UnlockView()
                case .unlocked: VaultView()
                }
            } else {
                ContentUnavailableView(
                    "Silicon Wallet Can't Open Its Vault", systemImage: "exclamationmark.lock",
                    description: Text(model.startupError ?? "Unknown error."))
            }
        }
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

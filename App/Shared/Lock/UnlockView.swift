import SiliconWalletKit
import SwiftUI

/// The locked screen: the master password, or Face ID / Touch ID when allowed, unlocks the vault.
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @State private var password = ""
    @State private var isWorking = false
    @State private var failed = false
    @State private var triedBiometrics = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Silicon Wallet Is Locked")
                .font(.title.bold())

            VStack(spacing: 8) {
                SecureField("Master password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(unlock)
                    .frame(maxWidth: 320)
                Text(failed ? "That password is wrong. Try again." : " ")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityHidden(!failed)
            }

            HStack(spacing: 12) {
                Button(action: unlock) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock").frame(minWidth: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isWorking)
                .keyboardShortcut(.defaultAction)

                if lock.canUnlockWithBiometrics {
                    Button("Unlock with \(lock.biometricKind.name)", systemImage: lock.biometricKind.symbol) {
                        Task { await lock.unlockWithBiometrics() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("Unlock with \(lock.biometricKind.name)")
                }
            }
            .controlSize(.large)

            if let notice = lock.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(32)
        .onAppear {
            isFocused = true
            if !triedBiometrics, lock.canUnlockWithBiometrics {
                triedBiometrics = true
                Task { await lock.unlockWithBiometrics() }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty, !isWorking, let session = model.session else { return }
        isWorking = true
        failed = false
        Task {
            do {
                try await session.unlock(password: password)
                password = ""
                lock.didUnlockWithPassword()
            } catch VaultError.wrongPassword {
                failed = true
                password = ""
                isFocused = true
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
            isWorking = false
        }
    }
}

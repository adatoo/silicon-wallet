import LocalAuthentication
import SiliconWalletKit
import SwiftUI

/// The locked screen: the master password, or Face ID / Touch ID when allowed, unlocks the vault.
/// On the Mac, Touch ID is shown inside the window (DESIGN.md §5).
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var isWorking = false
    @State private var failed = false
    @State private var triedBiometrics = false
    @FocusState private var isFocused: Bool
    #if os(macOS)
        /// The context the inline Touch ID view shows. A new one is made for each attempt.
        @State private var biometricContext: LAContext?
    #endif

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

                #if os(iOS)
                    if lock.canUnlockWithBiometrics {
                        Button("Unlock with \(lock.biometricKind.name)", systemImage: lock.biometricKind.symbol) {
                            Task { await lock.unlockWithBiometrics() }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    }
                #endif
            }
            .controlSize(.large)

            #if os(macOS)
                if lock.canUnlockWithBiometrics {
                    inlineTouchID
                }
            #endif

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
            startBiometricsOnce()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startBiometricsOnce() }
        }
        #if os(macOS)
            .onChange(of: password) { _, new in
                // Typing the password takes over from Touch ID.
                if !new.isEmpty { stopBiometrics() }
            }
            .onDisappear(perform: stopBiometrics)
        #endif
    }

    #if os(macOS)
        /// Touch ID inside the lock screen, instead of the system's floating panel.
        @ViewBuilder
        private var inlineTouchID: some View {
            if let biometricContext {
                VStack(spacing: 6) {
                    LocalAuthenticationView(context: biometricContext) {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .controlSize(.large)
                    Text("Touch ID or enter your password")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Use Touch ID", systemImage: "touchid", action: startBiometrics)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    #endif

    /// Offers Face ID or Touch ID once, as the screen appears. On iPhone and iPad it waits until
    /// the app is active: a prompt asked for while it's still coming to the front fails.
    private func startBiometricsOnce() {
        #if os(iOS)
            guard scenePhase == .active else { return }
        #endif
        guard !triedBiometrics, lock.canUnlockWithBiometrics else { return }
        triedBiometrics = true
        startBiometrics()
    }

    private func startBiometrics() {
        #if os(macOS)
            let context = LAContext()
            context.localizedCancelTitle = "Use Password"
            biometricContext = context
            Task {
                await lock.unlockWithBiometrics(context: context)
                if biometricContext === context { biometricContext = nil }
            }
        #else
            Task { await lock.unlockWithBiometrics() }
        #endif
    }

    #if os(macOS)
        private func stopBiometrics() {
            biometricContext?.invalidate()
            biometricContext = nil
        }
    #endif

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

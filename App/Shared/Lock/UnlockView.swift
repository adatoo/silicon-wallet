import LocalAuthentication
import SiliconWalletKit
import SwiftUI

/// The locked screen: Face ID / Touch ID or the master password unlocks the vault. With biometrics
/// on, it leads with them and shows the password field only on request, or when the prompt is
/// cancelled. On the Mac, Touch ID is shown inside the window (DESIGN.md §5). The form sits on a
/// frosted card over the backdrop.
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var isWorking = false
    @State private var failed = false
    /// After too many wrong passwords, when the next attempt may be made (`UnlockThrottle`).
    @State private var retryAt: Date?
    @State private var triedBiometrics = false
    /// Asked for the password field, by "Use Password" or by cancelling the biometric prompt.
    @State private var wantsPassword = false
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
                .multilineTextAlignment(.center)

            if showsPassword {
                passwordForm
            } else {
                biometricsFirst
            }

            if let notice = lock.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(32)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LockBackdrop() }
        .onAppear {
            isFocused = showsPassword
            retryAt = model.session?.nextPasswordAttempt
            startBiometricsOnce()
        }
        .task(id: retryAt) {
            // The field comes back when the wait is over.
            guard let retryAt else { return }
            try? await Task.sleep(for: .seconds(max(0, retryAt.timeIntervalSinceNow)))
            if !Task.isCancelled {
                self.retryAt = nil
                if showsPassword { isFocused = true }
            }
        }
        .onChange(of: showsPassword) { _, shows in
            // The field only exists once it shows, so focus it then.
            if shows { isFocused = true }
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

    /// The password field shows unless biometrics can unlock and it hasn't been asked for.
    private var showsPassword: Bool { wantsPassword || !lock.canUnlockWithBiometrics }

    private var passwordForm: some View {
        Group {
            VStack(spacing: 8) {
                SecureField("Master password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(unlock)
                    .frame(maxWidth: 320)
                    .disabled(retryAt != nil)
                passwordMessage
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
                .disabled(password.isEmpty || isWorking || retryAt != nil)
                .keyboardShortcut(.defaultAction)

                #if os(iOS)
                    if lock.canUnlockWithBiometrics {
                        Button("Unlock with \(lock.biometricKind.name)", systemImage: lock.biometricKind.symbol) {
                            startBiometrics()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    }
                #endif
            }
            .controlSize(.large)

            #if os(macOS)
                if lock.canUnlockWithBiometrics {
                    Button("Use Touch ID", systemImage: "touchid", action: useBiometrics)
                        .buttonStyle(.borderless)
                }
            #endif
        }
    }

    /// Under the field: a countdown while too many wrong passwords hold it back, how many tries
    /// are left before that, or that the password was wrong. Every message takes the same box, the
    /// field's width and two lines tall at the current text size, so the card never changes size.
    private var passwordMessage: some View {
        ZStack {
            // The longest message, unseen, sets the box's height.
            Text("Too many wrong passwords.\nTry again in 0:00:00.")
                .hidden()
                .accessibilityHidden(true)
            message
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private var message: some View {
        if let retryAt {
            Text(
                "Too many wrong passwords.\nTry again in \(Text(timerInterval: Date.now...retryAt, countsDown: true)).")
        } else if failed {
            Text(wrongPasswordMessage)
        }
    }

    private var wrongPasswordMessage: String {
        switch model.session?.passwordAttemptsBeforeDelay ?? UnlockThrottle.freeAttempts {
        case 1: "Wrong password. 1 more try before a 1-minute wait."
        case 2: "Wrong password. 2 more tries before a 1-minute wait."
        default: "That password is wrong."
        }
    }

    /// Face ID or Touch ID, with the password a button away.
    private var biometricsFirst: some View {
        VStack(spacing: 12) {
            #if os(iOS)
                Button(action: startBiometrics) {
                    Label("Unlock with \(lock.biometricKind.name)", systemImage: lock.biometricKind.symbol)
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            #else
                inlineTouchID
            #endif
            Button("Use Password", action: usePassword)
                .buttonStyle(.borderless)
        }
    }

    private func usePassword() {
        #if os(macOS)
            stopBiometrics()
        #endif
        wantsPassword = true
    }

    #if os(macOS)
        /// Back from the password field to Touch ID; cancelling brings the field back.
        private func useBiometrics() {
            password = ""
            failed = false
            wantsPassword = false
            startBiometrics()
        }
        /// Touch ID inside the lock screen, instead of the system's floating panel.
        @ViewBuilder
        private var inlineTouchID: some View {
            if let biometricContext {
                VStack(spacing: 6) {
                    LocalAuthenticationView(context: biometricContext) {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .controlSize(.regular)
                    Text("Touch ID or use your password")
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
                let unlocked = await lock.unlockWithBiometrics(context: context)
                if biometricContext === context {
                    biometricContext = nil
                    if !unlocked { usePassword() }
                }
            }
        #else
            Task {
                // Cancelling the prompt ("Use Password") or failing brings up the password field.
                if !(await lock.unlockWithBiometrics()) { usePassword() }
            }
        #endif
    }

    #if os(macOS)
        private func stopBiometrics() {
            biometricContext?.invalidate()
            biometricContext = nil
        }
    #endif

    /// Reads a message out with VoiceOver, which doesn't notice text changing under the field.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private func unlock() {
        guard !password.isEmpty, !isWorking, retryAt == nil, let session = model.session else { return }
        // The last message stays while this attempt is checked, rather than blinking out.
        isWorking = true
        Task {
            do {
                try await session.unlock(password: password)
                password = ""
                failed = false
                lock.didUnlockWithPassword()
            } catch VaultError.wrongPassword {
                failed = true
                password = ""
                retryAt = session.nextPasswordAttempt
                isFocused = retryAt == nil
                announce(retryAt == nil ? wrongPasswordMessage : "Too many wrong passwords. Wait before trying again.")
            } catch VaultError.tooManyAttempts(let until) {
                password = ""
                retryAt = until
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
            isWorking = false
        }
    }
}

/// A blurred circuit board in the icon's colours behind the lock screen (`task backdrop` draws it).
private struct LockBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .overlay {
                Image("LockBackdrop")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.08))
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

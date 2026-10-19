import SiliconWalletKit
import SwiftUI

/// Lock, clipboard and vault settings: the Settings window on the Mac, a sheet on iOS.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var changingPassword = false
    @State private var showingLog = false
    @State private var deletingVault = false
    @State private var showingAbout = false

    private static let autoLockChoices = [1, 2, 5, 10, 15, 30, 60, 0]
    private static let clipboardChoices = [15, 30, 60, 120, 300, 0]
    private static let graceChoices = [0, 30, 60, 300, 900]
    private static let reentryChoices = [1, 3, 7, 14, 30]

    var body: some View {
        @Bindable var settings = lock.settings
        let isUnlocked = model.session?.isUnlocked == true
        Form {
            Section("Locking") {
                Picker("Lock after inactivity", selection: $settings.autoLockMinutes) {
                    ForEach(Self.autoLockChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Never" : "\(minutes) min").tag(minutes)
                    }
                }
                #if os(macOS)
                    Toggle("Lock on sleep, screensaver and screen lock", isOn: $settings.lockOnSleep)
                #else
                    Picker("Lock in the background", selection: $settings.backgroundGraceSeconds) {
                        ForEach(Self.graceChoices, id: \.self) { seconds in
                            Text(Self.duration(seconds, zero: "Immediately")).tag(seconds)
                        }
                    }
                #endif
            }

            Section {
                Toggle(
                    "Unlock with \(lock.biometricKind.name)",
                    isOn: Binding(get: { settings.biometricsEnabled }, set: { lock.setBiometrics(enabled: $0) })
                )
                .disabled(lock.biometricKind == .none || (!isUnlocked && !settings.biometricsEnabled))
                Picker("Require password every", selection: $settings.passwordReentryDays) {
                    ForEach(Self.reentryChoices, id: \.self) { days in
                        Text(days == 1 ? "Day" : "\(days) days").tag(days)
                    }
                }
                .disabled(!settings.biometricsEnabled)
            } header: {
                Text(lock.biometricKind == .none ? "Biometrics" : lock.biometricKind.name)
            } footer: {
                Text(
                    lock.biometricKind == .none
                        ? "This device has no Face ID or Touch ID set up."
                        : "Your master password is still needed after a restart, and at least this often."
                )
            }

            Section {
                Picker(
                    "Clear copied values after",
                    selection: Binding(get: { settings.clipboardSeconds }, set: { lock.setClipboardSeconds($0) })
                ) {
                    ForEach(Self.clipboardChoices, id: \.self) { seconds in
                        Text(Self.duration(seconds, zero: "Never")).tag(seconds)
                    }
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Copied values are also cleared when the vault locks, if nothing else has been copied since.")
            }

            Section("iCloud Sync") {
                if let sync = model.sync {
                    Label(sync.status.summary, systemImage: sync.status.symbol)
                    Button("Sync Now") { Task { await sync.syncNow() } }
                } else {
                    Label(
                        "Sync is off in this build. Signed App Store and TestFlight builds sync through iCloud.",
                        systemImage: "icloud.slash")
                }
            }

            Section("Vault") {
                Button("Change Master Password…") { changingPassword = true }
                    .disabled(!isUnlocked)
                Button("Import from Acrylic Wallet…") {
                    model.isImportingAcrylic = true
                    #if os(iOS)
                        dismiss()
                    #endif
                }
                .disabled(!isUnlocked)
                Button("Access Log…") { showingLog = true }
                    .disabled(!isUnlocked)
                Button("Lock Now") {
                    lock.lockNow()
                    dismiss()
                }
                .disabled(!isUnlocked)
            }

            Section {
                Button("Delete Vault…", role: .destructive) { deletingVault = true }
                    .disabled(!isUnlocked)
            }

            Section {
                LabeledContent("Version", value: Self.version)
                HelpButton(title: "Silicon Wallet Help")
                Button("About Silicon Wallet…") { showingAbout = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
        #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        #endif
        .sheet(isPresented: $changingPassword) {
            NavigationStack { ChangePasswordView() }
        }
        .sheet(isPresented: $showingLog) {
            NavigationStack {
                AccessLogView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLog = false } }
                }
            }
        }
        .sheet(isPresented: $deletingVault) {
            NavigationStack { DeleteVaultView() }
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAbout = false } }
                }
            }
        }
    }

    static func duration(_ seconds: Int, zero: String) -> String {
        switch seconds {
        case 0: zero
        case ..<60: "\(seconds) s"
        default: "\(seconds / 60) min"
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Re-wraps the vault key under a new master password (DESIGN.md §5).
struct ChangePasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var wrongCurrent = false

    private var problem: String? {
        if current.isEmpty { return "Enter your current password." }
        if new.count < SetupView.minimumLength { return "Use at least \(SetupView.minimumLength) characters." }
        if new != confirmation { return "The new passwords don't match." }
        return nil
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
                if wrongCurrent {
                    Text("That isn't your current password.").font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                SecureField("New password", text: $new)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmation)
                    .textContentType(.newPassword)
                PasswordStrengthView(password: new)
            } footer: {
                Text(problem ?? "Your entries aren't re-encrypted; only the key that protects them changes.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Change Master Password")
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Change", action: change).disabled(problem != nil)
                }
            }
        }
    }

    private func change() {
        guard problem == nil, let session = model.session else { return }
        isWorking = true
        wrongCurrent = false
        Task {
            do {
                try await session.changePassword(current: current, new: new)
                lock.didUnlockWithPassword()
                dismiss()
            } catch VaultError.wrongPassword {
                wrongCurrent = true
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
            isWorking = false
        }
    }
}

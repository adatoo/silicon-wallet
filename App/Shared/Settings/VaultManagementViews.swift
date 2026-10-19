import SiliconWalletKit
import SwiftUI

extension AccessEvent.Kind {
    var title: String {
        switch self {
        case .unlockedWithPassword: "Unlocked with password"
        case .unlockedWithBiometrics: "Unlocked with Face ID or Touch ID"
        case .failedUnlock: "Failed unlock attempt"
        case .passwordChanged: "Master password changed"
        case .imported: "Imported from Acrylic Wallet"
        case .exported: "Attachment saved as a copy"
        case .vaultCreated: "Vault created"
        }
    }

    var symbol: String {
        switch self {
        case .unlockedWithPassword: "lock.open"
        case .unlockedWithBiometrics: "faceid"
        case .failedUnlock: "exclamationmark.lock"
        case .passwordChanged: "key"
        case .imported: "square.and.arrow.down"
        case .exported: "square.and.arrow.up"
        case .vaultCreated: "sparkles"
        }
    }
}

/// This device's access log (DESIGN.md §5), newest first.
struct AccessLogView: View {
    @Environment(AppModel.self) private var model
    @State private var events: [AccessEvent] = []

    var body: some View {
        List(events) { event in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.kind.title)
                    if let detail = event.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: event.kind.symbol)
                    .foregroundStyle(event.kind == .failedUnlock ? .red : .accentColor)
            }
        }
        .overlay {
            if events.isEmpty { ContentUnavailableView("No Activity Yet", systemImage: "list.bullet.rectangle") }
        }
        .navigationTitle("Access Log")
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
        #endif
        .onAppear { events = model.session?.accessEvents() ?? [] }
    }
}

/// Deletes the vault after the master password is confirmed: from this device only, or, with
/// sync, from iCloud and every device.
struct DeleteVaultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var everywhere = true
    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Text(
                    "This permanently deletes every group, entry and attachment in your vault. It can't be undone, and Silicon Wallet can't recover it."
                )
                if model.sync != nil {
                    Picker("Delete from", selection: $everywhere) {
                        Text("iCloud and all my devices").tag(true)
                        Text("This device only").tag(false)
                    }
                    .pickerStyle(.inline)
                    if !everywhere {
                        Text("Your vault stays in iCloud and comes back to this device when it next syncs.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                SecureField("Master password", text: $password)
                    .textContentType(.password)
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text("Type your master password to confirm.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Delete Vault")
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Delete", role: .destructive, action: delete).disabled(password.isEmpty)
                }
            }
        }
    }

    private func delete() {
        guard let session = model.session else { return }
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            guard (try? await session.verifyPassword(password)) == true else {
                problem = "That password is wrong."
                return
            }
            do {
                if everywhere, let sync = model.sync {
                    try await sync.deleteFromICloud()
                }
                TemporaryPreviews.removeAll()
                Clipboard.clearIfOurs()
                BiometricKeychain.delete()
                try session.deleteVault()
                model.entrySelection = nil
                model.sidebarSelection = .all
                dismiss()
            } catch {
                problem = "The vault couldn't be deleted: \(AppModel.describe(error))"
            }
        }
    }
}

/// Version, licence, privacy and source.
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tint)
                    Text("Silicon Wallet").font(.title2.bold())
                    Text("Version \(SettingsView.version)").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Privacy") {
                Text(
                    "Silicon Wallet collects no data. Your vault is encrypted on your device with a key made from your master password, and only encrypted data is stored or synced. Apple can't read it, and neither can anyone else."
                )
            }
            Section("Licence") {
                Text("Copyright © 2026 Arif Datoo. Free and open source under the MIT Licence.")
                Text("Argon2id comes from libsodium (ISC Licence), through swift-sodium.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Links") {
                Link(destination: AppLinks.support) { Label("Support", systemImage: "questionmark.circle") }
                Link(destination: AppLinks.privacy) { Label("Privacy Policy", systemImage: "hand.raised") }
                Link(destination: AppLinks.source) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}

import SiliconWalletKit
import SwiftUI

extension VaultSync.Status {
    var symbol: String {
        switch self {
        case .starting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .idle: "checkmark.icloud"
        case .noAccount: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }

    var summary: String {
        switch self {
        case .starting: "Starting iCloud sync…"
        case .syncing: "Syncing with iCloud…"
        case .idle(let lastSync):
            lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Up to date with iCloud"
        case .noAccount: "iCloud is unavailable. Sign in to iCloud to sync; everything stays on this device meanwhile."
        case .failed(let message): "Sync problem: \(message)"
        }
    }
}

/// The toolbar's sync indicator; tapping it syncs now.
struct SyncStatusButton: View {
    let sync: VaultSync

    var body: some View {
        Button {
            Task { await sync.syncNow() }
        } label: {
            Label("iCloud Sync", systemImage: sync.status.symbol)
                .symbolEffect(.pulse, isActive: sync.status == .syncing)
        }
        .help(sync.status.summary)
        .accessibilityValue(sync.status.summary)
    }
}

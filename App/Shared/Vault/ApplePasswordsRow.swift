import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Where a password kept in Apple Passwords would be (DESIGN.md §3). Apple Passwords can't be
/// read or linked to by other apps, so this only says so; on a Mac it can open the Passwords app.
struct ApplePasswordsRow: View {
    let label: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Label("In Apple Passwords", systemImage: "key.icloud")
                    .foregroundStyle(.secondary)
                #if os(macOS)
                    if let app = Self.passwordsApp {
                        Button("Open Passwords", systemImage: "arrow.up.right.square") {
                            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open the Passwords app")
                    }
                #endif
            }
        } label: {
            Text(label)
        }
    }

    #if os(macOS)
        private static var passwordsApp: URL? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords")
        }
    #endif
}

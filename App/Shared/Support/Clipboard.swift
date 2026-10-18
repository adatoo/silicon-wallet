import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Copies values for pasting elsewhere, and clears them again (DESIGN.md §5):
/// - concealed values are local-only on iOS, and marked concealed and transient on macOS, so
///   clipboard managers and Universal Clipboard leave them alone;
/// - every copy clears itself after `clearAfter` seconds, unless something else has been copied
///   since;
/// - `clearIfOurs()` runs on lock.
@MainActor
enum Clipboard {
    /// Seconds before a copied value is cleared; 0 means never. Set from `LockSettings`.
    static var clearAfter = 60
    private static var ourChangeCount: Int?
    private static var clearTask: Task<Void, Never>?

    static func copy(_ value: String, concealed: Bool) {
        #if os(iOS)
            var options: [UIPasteboard.OptionsKey: Any] = [:]
            if concealed { options[.localOnly] = true }
            if clearAfter > 0 { options[.expirationDate] = Date.now.addingTimeInterval(TimeInterval(clearAfter)) }
            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: value]], options: options)
            ourChangeCount = UIPasteboard.general.changeCount
        #else
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            if concealed {
                pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            }
            ourChangeCount = pasteboard.changeCount
        #endif

        clearTask?.cancel()
        guard clearAfter > 0 else { return }
        let delay = clearAfter
        clearTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            clearIfOurs()
        }
    }

    /// Clears the clipboard if it still holds the last value we copied.
    static func clearIfOurs() {
        guard let ours = ourChangeCount else { return }
        #if os(iOS)
            if UIPasteboard.general.changeCount == ours { UIPasteboard.general.items = [] }
        #else
            if NSPasteboard.general.changeCount == ours { NSPasteboard.general.clearContents() }
        #endif
        ourChangeCount = nil
        clearTask?.cancel()
        clearTask = nil
    }
}

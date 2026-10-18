import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Copies values for pasting elsewhere. Concealed values are marked so clipboard managers and
/// Universal Clipboard leave them alone (DESIGN.md §5).
@MainActor
enum Clipboard {
    static func copy(_ value: String, concealed: Bool) {
        #if os(iOS)
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: value]], options: concealed ? [.localOnly: true] : [:])
        #else
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            if concealed {
                pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            }
        #endif
    }
}

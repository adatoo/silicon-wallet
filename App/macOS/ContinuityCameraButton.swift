import AppKit
import SwiftUI

/// A button that takes a photo with a nearby iPhone or iPad through Continuity Camera and hands
/// it over in memory (ADR-0009). The photo comes through the pasteboard AppKit gives this
/// button, is never saved, and needs no camera access on the Mac.
struct ContinuityCameraButton: NSViewRepresentable {
    let title: String
    let onPhoto: (CGImage) -> Void

    func makeNSView(context: Context) -> PhotoRequestButton {
        let button = PhotoRequestButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.onPhoto = onPhoto
        return button
    }

    func updateNSView(_ button: PhotoRequestButton, context: Context) {
        button.title = title
        button.onPhoto = onPhoto
    }

    final class PhotoRequestButton: NSButton, @preconcurrency NSServicesMenuRequestor {
        var onPhoto: ((CGImage) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            // AppKit fills a menu item with this identifier with the nearby devices and their
            // Take Photo commands, and sends the photo to the first responder that asks for images.
            window?.makeFirstResponder(self)
            let menu = NSMenu()
            let item = NSMenuItem(title: "Take Photo", action: nil, keyEquivalent: "")
            item.identifier = NSMenuItem.importFromDeviceIdentifier
            menu.addItem(item)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        override func validRequestor(
            forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
        ) -> Any? {
            if sendType == nil, let returnType, NSImage.imageTypes.contains(returnType.rawValue) { return self }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        func readSelection(from pasteboard: NSPasteboard) -> Bool {
            guard let image = NSImage(pasteboard: pasteboard),
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            onPhoto?(cgImage)
            return true
        }

        func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    }
}

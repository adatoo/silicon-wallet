import AppKit
import SwiftUI

/// A button that takes a photo with a nearby iPhone or iPad through Continuity Camera and hands
/// it over in memory (ADR-0009). The photo comes through the pasteboard AppKit gives this
/// button, is never saved, and needs no camera access on the Mac.
struct ContinuityCameraButton: NSViewRepresentable {
    let title: String
    let onPhoto: (CGImage) -> Void

    func makeNSView(context: Context) -> PhotoRequestButton {
        let button = PhotoRequestButton(frame: .zero)
        button.title = title
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

    /// Not final, so a test can watch what AppKit asks it.
    class PhotoRequestButton: NSButton, @preconcurrency NSServicesMenuRequestor {
        var onPhoto: ((CGImage) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            // Space or Return on a focused button, which doesn't come through mouseDown.
            target = self
            action = #selector(activate)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            target = self
            action = #selector(activate)
        }

        override func mouseDown(with event: NSEvent) { presentMenu(makeMenu()) }

        @objc private func activate(_ sender: Any?) { presentMenu(makeMenu()) }

        /// AppKit adds its Import from iPhone or iPad items (Take Photo, Scan Documents) to a
        /// context menu whose view accepts images (`validRequestor`). It doesn't fill them into a
        /// pop-up menu, which is why this is a context menu.
        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            for note in [
                "Choose Take Photo or Scan Documents below.", "Not listed? Unlock your iPhone and keep it nearby.",
            ] {
                let item = NSMenuItem(title: note, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            return menu
        }

        /// Shows `menu` under the button, as a context menu for it.
        func presentMenu(_ menu: NSMenu) {
            guard let window else { return }
            window.makeFirstResponder(self)
            let location = convert(NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), to: nil)
            guard
                let event = NSEvent.mouseEvent(
                    with: .rightMouseDown, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)
            else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func validRequestor(
            forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
        ) -> Any? {
            if sendType == nil, let returnType, NSImage.imageTypes.contains(returnType.rawValue) { return self }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        func readSelection(from pasteboard: NSPasteboard) -> Bool {
            // Scan Documents sends a PDF, whose size is in points; drawn at that size its text
            // is too small to read, so it's drawn at three times.
            if let data = pasteboard.data(forType: .pdf), let page = Self.render(pdf: data, scale: 3) {
                onPhoto?(page)
                return true
            }
            guard let image = NSImage(pasteboard: pasteboard),
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            onPhoto?(cgImage)
            return true
        }

        /// The PDF's first page as an image, in memory.
        static func render(pdf data: Data, scale: CGFloat) -> CGImage? {
            guard let provider = CGDataProvider(data: data as CFData),
                let document = CGPDFDocument(provider), let page = document.page(at: 1)
            else { return nil }
            let box = page.getBoxRect(.cropBox)
            let width = Int(box.width * scale)
            let height = Int(box.height * scale)
            guard width > 0, height > 0,
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return context.makeImage()
        }

        func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    }
}

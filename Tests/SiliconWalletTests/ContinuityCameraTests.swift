#if os(macOS)
    import AppKit
    import Testing

    @testable import SiliconWallet

    /// Records the return types AppKit asks the button about.
    private final class RecordingButton: ContinuityCameraButton.PhotoRequestButton {
        var askedFor: [String] = []

        override func validRequestor(
            forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
        ) -> Any? {
            if sendType == nil, let returnType { askedFor.append(returnType.rawValue) }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }
    }

    /// Closes the menu shortly after it opens, so the test doesn't wait for a click.
    private final class Closer: NSObject, NSMenuDelegate {
        private weak var menu: NSMenu?

        func menuWillOpen(_ menu: NSMenu) {
            self.menu = menu
            // In the common modes, so it fires while the menu is tracking.
            let timer = Timer(
                timeInterval: 0.5, target: self, selector: #selector(close), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
        }

        @objc private func close() { menu?.cancelTracking() }
    }

    /// The menu is where AppKit offers Continuity Camera; it does so only when it asks the button
    /// for images, which it didn't for the pop-up menu 1.7.0 used (#143).
    @MainActor
    @Test func theScanMenuAsksTheButtonForImages() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 320, height: 80), styleMask: [.titled], backing: .buffered,
            defer: false)
        // Owned by this test, not released by close(), which would crash the host later.
        window.isReleasedWhenClosed = false
        let button = RecordingButton(frame: NSRect(x: 20, y: 20, width: 200, height: 30))
        let container = NSView(frame: window.contentRect(forFrameRect: window.frame))
        container.addSubview(button)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)

        let menu = button.makeMenu()
        let closer = Closer()
        menu.delegate = closer
        button.presentMenu(menu)

        #expect(button.askedFor.contains("public.jpeg"))
        #expect(button.validRequestor(forSendType: nil, returnType: .png) as AnyObject? === button)
        #expect(button.validRequestor(forSendType: nil, returnType: .string) == nil)
        window.close()
    }
#endif

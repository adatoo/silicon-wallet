import AppKit

/// Sizes the main window for Mac App Store screenshots (`task screenshots:mac`, launch argument
/// `-ScreenshotWindowSize <width>x<height>` with the demo vault). The window stops saving its
/// frame first, so a screenshot launch never moves or resizes the real app's window.
@MainActor
enum ScreenshotWindow {
    static func resize(to value: String) {
        let parts = value.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        Task { @MainActor in
            // The window appears after the demo vault fills; give SwiftUI a moment to show it.
            try? await Task.sleep(for: .milliseconds(500))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
            else { return }
            window.setFrameAutosaveName("")
            window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            window.center()
        }
    }
}

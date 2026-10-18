import SwiftUI
import UIKit

/// Notices every touch in the window, without taking part in it, so auto-lock can tell the app
/// is in use (DESIGN.md §5).
struct ActivityRecognizerInstaller: UIViewRepresentable {
    let onActivity: @MainActor () -> Void

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(onActivity: onActivity)
    }

    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let onActivity: @MainActor () -> Void
        private weak var installedIn: UIWindow?

        init(onActivity: @escaping @MainActor () -> Void) {
            self.onActivity = onActivity
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, installedIn !== window else { return }
            window.addGestureRecognizer(ActivityGestureRecognizer(onActivity: onActivity))
            installedIn = window
        }
    }
}

/// Records a touch, then fails at once so it never blocks or delays the touch it saw.
private final class ActivityGestureRecognizer: UIGestureRecognizer {
    private let onActivity: @MainActor () -> Void

    init(onActivity: @escaping @MainActor () -> Void) {
        self.onActivity = onActivity
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onActivity()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Covers the window in the app switcher and while inactive, so a snapshot never shows the vault.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Silicon Wallet")
                    .font(.title2.bold())
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

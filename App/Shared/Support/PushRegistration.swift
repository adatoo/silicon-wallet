import SwiftUI

#if os(iOS)
    import UIKit

    /// Registers for remote notifications, which `CKSyncEngine` uses to hear about changes from
    /// other devices (DESIGN.md §7).
    final class PushRegistration: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool {
            if CloudEntitlement.isAvailable, !ProcessInfo.processInfo.arguments.contains("-InMemoryVault") {
                application.registerForRemoteNotifications()
            }
            return true
        }
    }
#else
    import AppKit

    /// Registers for remote notifications, which `CKSyncEngine` uses to hear about changes from
    /// other devices (DESIGN.md §7).
    final class PushRegistration: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            if CloudEntitlement.isAvailable, !ProcessInfo.processInfo.arguments.contains("-InMemoryVault") {
                NSApplication.shared.registerForRemoteNotifications()
            }
        }
    }
#endif

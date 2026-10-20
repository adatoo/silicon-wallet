import Foundation
import Security
import SiliconWalletKit

#if os(iOS)
    import UIKit
#endif

/// Whether this build can use iCloud. CloudKit traps if the app lacks the container entitlement,
/// so ad-hoc `task dev` builds, tests and the demo vault stay local (DESIGN.md §7).
enum CloudEntitlement {
    static let containerIdentifier = "iCloud.com.datoos.silicon-wallet"

    static var isAvailable: Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                let value = SecTaskCopyValueForEntitlement(
                    task, "com.apple.developer.icloud-container-identifiers" as CFString, nil),
                let containers = value as? [String]
            else { return false }
            return containers.contains(containerIdentifier)
        #else
            // iOS builds that run are always signed with their entitlements; the simulator
            // builds CI makes are never run.
            return true
        #endif
    }

    /// Debug builds sync with CloudKit Development. Release builds sync with Production: the
    /// Release entitlements say so, so a Release build run from Xcode does too.
    static var environment: CloudEnvironment {
        #if DEBUG
            .development
        #else
            .production
        #endif
    }
}

/// This device's name, for conflict copies ("… (conflict copy, Jane's iPhone, …)").
@MainActor
enum DeviceName {
    static var current: String {
        #if os(iOS)
            UIDevice.current.name
        #else
            Host.current().localizedName ?? "Mac"
        #endif
    }
}

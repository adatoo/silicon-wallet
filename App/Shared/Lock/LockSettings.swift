import Foundation
import Observation
import SiliconWalletKit

/// The lock and clipboard preferences (DESIGN.md §5). These are app settings, not vault data, so
/// they live in `UserDefaults`; nothing secret is ever stored here.
@MainActor
@Observable
final class LockSettings {
    private let defaults: UserDefaults

    /// Minutes of inactivity before the vault locks; 0 means never.
    var autoLockMinutes: Int { didSet { defaults.set(autoLockMinutes, forKey: Key.autoLockMinutes) } }
    /// Seconds before a copied value is cleared from the clipboard; 0 means never.
    var clipboardSeconds: Int { didSet { defaults.set(clipboardSeconds, forKey: Key.clipboardSeconds) } }
    /// iOS: seconds in the background before the vault locks; 0 means at once.
    var backgroundGraceSeconds: Int {
        didSet { defaults.set(backgroundGraceSeconds, forKey: Key.backgroundGraceSeconds) }
    }
    /// macOS: lock on sleep, screensaver and screen lock.
    var lockOnSleep: Bool { didSet { defaults.set(lockOnSleep, forKey: Key.lockOnSleep) } }
    var biometricsEnabled: Bool { didSet { defaults.set(biometricsEnabled, forKey: Key.biometricsEnabled) } }
    /// Days before the master password is needed again, even with biometrics.
    var passwordReentryDays: Int {
        didSet { defaults.set(passwordReentryDays, forKey: Key.passwordReentryDays) }
    }
    /// When the master password last unlocked the vault.
    var lastPasswordUnlock: Date? { didSet { defaults.set(lastPasswordUnlock, forKey: Key.lastPasswordUnlock) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoLockMinutes: 5,
            Key.clipboardSeconds: 60,
            Key.backgroundGraceSeconds: 0,
            Key.lockOnSleep: true,
            Key.biometricsEnabled: false,
            Key.passwordReentryDays: 7,
        ])
        autoLockMinutes = defaults.integer(forKey: Key.autoLockMinutes)
        clipboardSeconds = defaults.integer(forKey: Key.clipboardSeconds)
        backgroundGraceSeconds = defaults.integer(forKey: Key.backgroundGraceSeconds)
        lockOnSleep = defaults.bool(forKey: Key.lockOnSleep)
        biometricsEnabled = defaults.bool(forKey: Key.biometricsEnabled)
        passwordReentryDays = defaults.integer(forKey: Key.passwordReentryDays)
        lastPasswordUnlock = defaults.object(forKey: Key.lastPasswordUnlock) as? Date
    }

    var biometricPolicy: BiometricPolicy {
        BiometricPolicy(isEnabled: biometricsEnabled, maximumAge: TimeInterval(passwordReentryDays) * 86_400)
    }

    private enum Key {
        static let autoLockMinutes = "autoLockMinutes"
        static let clipboardSeconds = "clipboardSeconds"
        static let backgroundGraceSeconds = "backgroundGraceSeconds"
        static let lockOnSleep = "lockOnSleep"
        static let biometricsEnabled = "biometricsEnabled"
        static let passwordReentryDays = "passwordReentryDays"
        static let lastPasswordUnlock = "lastPasswordUnlock"
    }
}

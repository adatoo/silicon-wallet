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
    /// Whether this device has offered Face ID or Touch ID once, after a password unlock.
    var biometricsOffered: Bool { didSet { defaults.set(biometricsOffered, forKey: Key.biometricsOffered) } }
    /// When to next ask whether the master password is still remembered (`PasswordReminder`).
    /// Not secret: only a date.
    var nextPasswordReminder: Date? {
        didSet { defaults.set(nextPasswordReminder, forKey: Key.nextPasswordReminder) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoLockMinutes: 5,
            Key.clipboardSeconds: 60,
            Key.backgroundGraceSeconds: 0,
            Key.lockOnSleep: true,
            Key.biometricsEnabled: false,
            Key.biometricsOffered: false,
        ])
        // Left by builds that asked for the password every few days and after a restart.
        for key in Key.retired { defaults.removeObject(forKey: key) }
        autoLockMinutes = defaults.integer(forKey: Key.autoLockMinutes)
        clipboardSeconds = defaults.integer(forKey: Key.clipboardSeconds)
        backgroundGraceSeconds = defaults.integer(forKey: Key.backgroundGraceSeconds)
        lockOnSleep = defaults.bool(forKey: Key.lockOnSleep)
        biometricsEnabled = defaults.bool(forKey: Key.biometricsEnabled)
        biometricsOffered = defaults.bool(forKey: Key.biometricsOffered)
        nextPasswordReminder = defaults.object(forKey: Key.nextPasswordReminder) as? Date
    }

    private enum Key {
        static let autoLockMinutes = "autoLockMinutes"
        static let clipboardSeconds = "clipboardSeconds"
        static let backgroundGraceSeconds = "backgroundGraceSeconds"
        static let lockOnSleep = "lockOnSleep"
        static let biometricsEnabled = "biometricsEnabled"
        static let biometricsOffered = "biometricsOffered"
        static let nextPasswordReminder = "nextPasswordReminder"
        static let retired = ["passwordReentryDays", "lastPasswordUnlock", "lastPasswordUnlockClock"]
    }
}

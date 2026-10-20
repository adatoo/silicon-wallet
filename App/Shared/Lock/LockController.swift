import Foundation
import LocalAuthentication
import Observation
import SiliconWalletKit

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Locks the vault when it should be (DESIGN.md §5): after inactivity, on sleep, screensaver and
/// screen lock on the Mac, and after time in the background on iOS. It also runs biometric
/// unlock, offers it once on a device where it's off, and reminds people of their password.
@MainActor
@Observable
final class LockController {
    let model: AppModel
    let settings: LockSettings

    /// A message for the unlock screen, such as why the password is needed this once.
    var notice: String?
    /// Asks, once per device, whether to turn on Face ID or Touch ID after a password unlock.
    var isOfferingBiometrics = false
    /// Asks whether the master password is still remembered (`PasswordReminder`).
    var isRemindingPassword = false

    @ObservationIgnored private var lastActivity = Date.now
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    #if os(macOS)
        @ObservationIgnored private var eventMonitor: Any?
    #endif

    init(model: AppModel, settings: LockSettings = LockSettings()) {
        self.model = model
        self.settings = settings
        Clipboard.clearAfter = settings.clipboardSeconds
        TemporaryPreviews.removeAll()
    }

    /// Starts watching for activity and system events. Call once, at launch.
    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.checkInactivity()
            }
        }
        #if os(macOS)
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
                observers.append(
                    workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.systemWillSleep() }
                    })
            }
            // The clipboard timer dies with the app, so clear on the way out.
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated { Clipboard.clearIfOurs() }
                })
            let distributed = DistributedNotificationCenter.default()
            for name in ["com.apple.screensaver.didstart", "com.apple.screenIsLocked"] {
                observers.append(
                    distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.systemWillSleep() }
                    })
            }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { [weak self] event in
                MainActor.assumeIsolated { self?.recordActivity() }
                return event
            }
        #endif
    }

    func recordActivity() {
        lastActivity = .now
    }

    /// Locks the vault and clears anything we left on the clipboard.
    func lockNow() {
        Clipboard.clearIfOurs()
        TemporaryPreviews.removeAll()
        model.lock()
        isRemindingPassword = false
    }

    private func checkInactivity() {
        guard model.session?.isUnlocked == true, settings.autoLockMinutes > 0 else { return }
        if Date.now.timeIntervalSince(lastActivity) >= TimeInterval(settings.autoLockMinutes * 60) {
            lockNow()
        }
    }

    private func systemWillSleep() {
        guard settings.lockOnSleep, model.session?.isUnlocked == true else { return }
        lockNow()
    }

    // MARK: - iOS background

    func didEnterBackground() {
        backgroundedAt = .now
        if settings.backgroundGraceSeconds == 0, model.session?.isUnlocked == true { lockNow() }
    }

    func didBecomeActive() {
        defer { backgroundedAt = nil }
        guard let backgroundedAt, model.session?.isUnlocked == true else { return }
        if Date.now.timeIntervalSince(backgroundedAt) >= TimeInterval(settings.backgroundGraceSeconds) {
            lockNow()
        } else {
            recordActivity()
        }
    }

    // MARK: - Unlocking

    /// Call after the master password has unlocked (or created) the vault.
    func didUnlockWithPassword() {
        settings.nextPasswordReminder = PasswordReminder.next(afterConfirmingAt: .now)
        recordActivity()
        notice = nil
        if settings.biometricsEnabled, let key = model.session?.vaultKeyForBiometricUnlock() {
            // Store it again, so it always matches this vault and the faces or fingerprints
            // enrolled now.
            try? BiometricKeychain.store(key)
        } else if !settings.biometricsOffered, biometricKind != .none {
            isOfferingBiometrics = true
        }
    }

    var biometricKind: BiometricKeychain.Kind { BiometricKeychain.availableKind }

    /// Whether the unlock screen should offer Face ID or Touch ID now. Once turned on, they work
    /// until the stored key is gone: the faces or fingerprints changed, or this is a new device.
    var canUnlockWithBiometrics: Bool {
        settings.biometricsEnabled && biometricKind != .none && BiometricKeychain.hasStoredKey
    }

    /// Unlocks with Face ID or Touch ID. With a `context`, the prompt shows wherever that context
    /// is displayed (the Mac lock screen's inline Touch ID); without one, the system shows its own.
    func unlockWithBiometrics(context: LAContext? = nil) async {
        guard let session = model.session else { return }
        let reason = "unlock your vault"
        do {
            let key =
                if let context {
                    try await BiometricKeychain.load(context: context, reason: reason)
                } else {
                    try await BiometricKeychain.load(reason: reason)
                }
            try session.unlock(vaultKey: key)
            recordActivity()
            notice = nil
            if settings.nextPasswordReminder == nil {
                settings.nextPasswordReminder = PasswordReminder.next(afterConfirmingAt: .now)
            }
            isRemindingPassword = PasswordReminder.isDue(next: settings.nextPasswordReminder, now: .now)
        } catch BiometricError.cancelled {
            // Fall back to the password field.
        } catch BiometricError.noStoredKey, VaultError.wrongPassword {
            // Biometrics stay on: the next password unlock stores a fresh key.
            BiometricKeychain.delete()
            notice =
                "\(biometricKind.name) needs your password once, because the faces or fingerprints on this device changed."
        } catch {
            notice = AppModel.describe(error)
        }
    }

    /// Turns biometric unlock on or off. Turning it on needs the vault unlocked.
    func setBiometrics(enabled: Bool) {
        if enabled {
            guard let key = model.session?.vaultKeyForBiometricUnlock() else { return }
            do {
                try BiometricKeychain.store(key)
                settings.biometricsEnabled = true
                if settings.nextPasswordReminder == nil {
                    settings.nextPasswordReminder = PasswordReminder.next(afterConfirmingAt: .now)
                }
            } catch {
                settings.biometricsEnabled = false
                model.errorMessage = "\(biometricKind.name) couldn't be turned on: \(error.localizedDescription)"
            }
        } else {
            BiometricKeychain.delete()
            settings.biometricsEnabled = false
        }
        settings.biometricsOffered = true
    }

    /// Answers the one-time offer to turn on Face ID or Touch ID.
    func answerBiometricOffer(turnOn: Bool) {
        isOfferingBiometrics = false
        if turnOn {
            setBiometrics(enabled: true)
        } else {
            settings.biometricsOffered = true
        }
    }

    /// Checks `password` for the reminder. Nothing locks on a wrong one; it can be tried again.
    func confirmPassword(_ password: String) async -> Bool {
        guard let session = model.session, (try? await session.verifyPassword(password)) == true else {
            return false
        }
        settings.nextPasswordReminder = PasswordReminder.next(afterConfirmingAt: .now)
        isRemindingPassword = false
        return true
    }

    /// "Not Now" on the reminder.
    func snoozePasswordReminder() {
        settings.nextPasswordReminder = PasswordReminder.next(afterSnoozingAt: .now)
        isRemindingPassword = false
    }

    func setClipboardSeconds(_ seconds: Int) {
        settings.clipboardSeconds = seconds
        Clipboard.clearAfter = seconds
    }
}

extension BiometricKeychain.Kind {
    var name: String {
        switch self {
        case .none: "Biometrics"
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        }
    }

    var symbol: String {
        switch self {
        case .none: "lock"
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        }
    }
}

import Foundation
import Observation
import SiliconWalletKit

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Locks the vault when it should be (DESIGN.md §5): after inactivity, on sleep, screensaver and
/// screen lock on the Mac, and after time in the background on iOS. It also runs biometric
/// unlock, and records password unlocks for the biometric re-entry rule.
@MainActor
@Observable
final class LockController {
    let model: AppModel
    let settings: LockSettings

    /// A message for the unlock screen, such as why biometrics were turned off.
    var notice: String?

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
        settings.lastPasswordUnlock = .now
        recordActivity()
        notice = nil
        if settings.biometricsEnabled, let key = model.session?.vaultKeyForBiometricUnlock() {
            // Refresh the stored key, so it always matches this vault.
            try? BiometricKeychain.store(key)
        }
    }

    var biometricKind: BiometricKeychain.Kind { BiometricKeychain.availableKind }

    /// Whether the unlock screen should offer Face ID or Touch ID now.
    var canUnlockWithBiometrics: Bool {
        biometricKind != .none
            && settings.biometricPolicy.allowsBiometricUnlock(
                lastPasswordUnlock: settings.lastPasswordUnlock, bootTime: BiometricPolicy.bootTime())
            && BiometricKeychain.hasStoredKey
    }

    func unlockWithBiometrics() async {
        guard let session = model.session else { return }
        do {
            let key = try await BiometricKeychain.load(reason: "Unlock your vault")
            try session.unlock(vaultKey: key)
            recordActivity()
            notice = nil
        } catch BiometricError.cancelled {
            // Fall back to the password field.
        } catch BiometricError.noStoredKey, VaultError.wrongPassword {
            BiometricKeychain.delete()
            settings.biometricsEnabled = false
            notice =
                "\(biometricKind.name) was turned off because its saved key no longer matches. Unlock with your password, then turn it on again in Settings."
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
                settings.lastPasswordUnlock = settings.lastPasswordUnlock ?? .now
            } catch {
                settings.biometricsEnabled = false
                model.errorMessage = "\(biometricKind.name) couldn't be turned on: \(error.localizedDescription)"
            }
        } else {
            BiometricKeychain.delete()
            settings.biometricsEnabled = false
        }
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

import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// When Face ID or Touch ID may stand in for the master password (DESIGN.md §5): only after the
/// password has been used since the device last started, and within `maximumAge` of that.
public struct BiometricPolicy: Equatable, Sendable {
    public static let defaultMaximumAge: TimeInterval = 7 * 24 * 60 * 60

    public var isEnabled: Bool
    public var maximumAge: TimeInterval

    public init(isEnabled: Bool, maximumAge: TimeInterval = defaultMaximumAge) {
        self.isEnabled = isEnabled
        self.maximumAge = maximumAge
    }

    /// - Parameters:
    ///   - lastPasswordUnlock: when the master password last unlocked the vault, if ever.
    ///   - bootTime: when the device last started.
    public func allowsBiometricUnlock(lastPasswordUnlock: Date?, bootTime: Date, now: Date = .now) -> Bool {
        guard isEnabled, let lastPasswordUnlock else { return false }
        return lastPasswordUnlock >= bootTime && now.timeIntervalSince(lastPasswordUnlock) <= maximumAge
            && lastPasswordUnlock <= now
    }

    /// When the device last started, from the time since boot.
    public static func bootTime(now: Date = .now, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date {
        now.addingTimeInterval(-uptime)
    }
}

/// Errors from the biometric Keychain item.
public enum BiometricError: Error, Equatable, Sendable {
    /// No Face ID or Touch ID is set up, or the device has none.
    case unavailable
    /// There's no stored key, or it was invalidated (for example, fingerprints changed).
    case noStoredKey
    /// The person cancelled, or authentication failed.
    case cancelled
    case keychain(OSStatus)
}

/// Keeps the vault key in the Keychain behind Face ID or Touch ID: `.biometryCurrentSet`,
/// `WhenUnlockedThisDeviceOnly`, never synced (DESIGN.md §5). Adding or removing a fingerprint
/// or face invalidates the item, so the master password is needed again.
public enum BiometricKeychain {
    static let service = "com.datoos.silicon-wallet.vault-key"
    static let account = "vault"

    public enum Kind: Sendable {
        case none
        case touchID
        case faceID
        case opticID
    }

    /// What this device offers, if biometrics are set up.
    public static var availableKind: Kind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .touchID: return .touchID
        case .faceID: return .faceID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public static func store(_ vaultKey: SymmetricKey) throws {
        guard availableKind != .none else { throw BiometricError.unavailable }
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil)
        else { throw BiometricError.unavailable }

        delete()
        var query = baseQuery
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = vaultKey.withUnsafeBytes { Data($0) }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw BiometricError.keychain(status) }
    }

    /// Asks for Face ID or Touch ID, then returns the stored vault key. The Keychain call blocks
    /// while the prompt shows, so it runs off the main actor.
    public static func load(reason: String) async throws -> SymmetricKey {
        let data: Data = try await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.localizedReason = reason
            context.localizedCancelTitle = "Use Password"
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { throw BiometricError.noStoredKey }
                return data
            case errSecItemNotFound: throw BiometricError.noStoredKey
            case errSecUserCanceled, errSecAuthFailed: throw BiometricError.cancelled
            default: throw BiometricError.keychain(status)
            }
        }.value
        return SymmetricKey(data: data)
    }

    public static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Whether a key is stored, without prompting.
    public static var hasStoredKey: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

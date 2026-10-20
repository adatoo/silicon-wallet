import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Errors from the biometric Keychain item.
public enum BiometricError: Error, Equatable, Sendable {
    /// No Face ID or Touch ID is set up, or the device has none.
    case unavailable
    /// There's no stored key, or it was invalidated (for example, fingerprints changed).
    case noStoredKey
    /// The person cancelled, or authentication failed.
    case cancelled
    /// Too many failed attempts; the device passcode or the master password is needed first.
    case lockedOut
    case keychain(OSStatus)
}

extension BiometricError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Face ID or Touch ID isn't set up on this device."
        case .noStoredKey: "The saved key for Face ID or Touch ID is missing."
        case .cancelled: "Face ID or Touch ID was cancelled."
        case .lockedOut: "Face ID or Touch ID is locked after too many attempts. Unlock with your password."
        case .keychain(let status):
            "The Keychain reported an error: \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown") (\(status))."
        }
    }
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

    /// Asks for Face ID or Touch ID, then returns the stored vault key. The Keychain shows its
    /// own prompt.
    public static func load(reason: String) async throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedCancelTitle = "Use Password"
        // No "Enter Password" button after a failed attempt: the password field is right there.
        context.localizedFallbackTitle = ""
        return try await read(context: context)
    }

    /// Asks for Touch ID through `context`, then returns the stored vault key. On the Mac the
    /// lock screen shows `context` in a `LocalAuthenticationView`, so the prompt appears inside
    /// the window rather than as a floating panel. The Keychain read reuses the approved context,
    /// so it doesn't ask again.
    @MainActor
    public static func load(context: LAContext, reason: String) async throws -> SymmetricKey {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { _, error in
                if let error {
                    continuation.resume(throwing: mapped(error))
                } else {
                    continuation.resume()
                }
            }
        }
        // The lock screen keeps the context only to display it; nothing else uses it until the
        // read returns.
        nonisolated(unsafe) let approved = context
        return try await read(context: approved)
    }

    /// Reads the key with `context`. The Keychain call blocks while any prompt shows, so it runs
    /// off the main actor.
    private static func read(context: sending LAContext) async throws -> SymmetricKey {
        let data: Data = try await Task.detached(priority: .userInitiated) {
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
            default: throw readFailure(status)
            }
        }.value
        return SymmetricKey(data: data)
    }

    /// What a failed Keychain read means. A face or finger that isn't recognised, a cancel, the
    /// password button and "not frontmost" all mean "use the password", quietly. The Keychain
    /// reports Face ID and Touch ID outcomes either as its own codes or as `LAError` codes.
    static func readFailure(_ status: OSStatus) -> BiometricError {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .cancelled
        default:
            guard let code = LAError.Code(rawValue: Int(status)) else { return .keychain(status) }
            return mapped(LAError(code)) as? BiometricError ?? .keychain(status)
        }
    }

    /// Cancelling, falling back to the password or failing too often all mean "use the password".
    static func mapped(_ error: any Error) -> any Error {
        guard let error = error as? LAError else { return error }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback, .authenticationFailed:
            return BiometricError.cancelled
        case .biometryNotAvailable, .biometryNotEnrolled:
            return BiometricError.unavailable
        case .biometryLockout:
            return BiometricError.lockedOut
        default:
            return error
        }
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

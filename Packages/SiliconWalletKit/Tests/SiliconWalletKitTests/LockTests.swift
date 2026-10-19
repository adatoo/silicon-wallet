import Foundation
import LocalAuthentication
import Testing

@testable import SiliconWalletKit

// MARK: - Generator

@Test(arguments: [8, 20, 64])
func passwordsHaveTheRequestedLength(length: Int) {
    #expect(PasswordGenerator.password(.init(length: length)).count == length)
}

@Test func passwordsUseEveryChosenSetAndNothingElse() {
    let options = PasswordGenerator.CharacterOptions(
        length: 12, lowercase: true, uppercase: false, digits: true, symbols: false)
    for _ in 0..<200 {
        let password = PasswordGenerator.password(options)
        #expect(password.contains { $0.isLowercase })
        #expect(password.contains { $0.isNumber })
        #expect(!password.contains { $0.isUppercase })
        #expect(password.allSatisfy { $0.isLowercase || $0.isNumber })
    }
}

@Test func ambiguousCharactersCanBeLeftOut() {
    let options = PasswordGenerator.CharacterOptions(length: 64, avoidAmbiguous: true)
    for _ in 0..<50 {
        #expect(!PasswordGenerator.password(options).contains(where: { "0Oo1lI|".contains($0) }))
    }
}

@Test func passwordsAreRandom() {
    let passwords = Set((0..<100).map { _ in PasswordGenerator.password() })
    #expect(passwords.count == 100)
}

@Test func tooShortALengthIsRaisedToTheMinimum() {
    #expect(PasswordGenerator.password(.init(length: 2)).count == 8)
}

@Test func passphrasesHaveTheRequestedShape() {
    let options = PasswordGenerator.WordOptions(wordCount: 6, separator: "-", capitalise: true, includeDigit: true)
    let words = PasswordGenerator.passphrase(options).split(separator: "-")
    #expect(words.count == 6)
    #expect(words.allSatisfy { $0.first?.isUppercase == true })
    #expect(words.filter { $0.last?.isNumber == true }.count == 1)
}

@Test func theWordlistIsCleanAndLargeEnough() {
    #expect(Wordlist.words.count >= 1024)
    #expect(Set(Wordlist.words).count == Wordlist.words.count)
    #expect(Wordlist.words.allSatisfy { $0.allSatisfy { $0.isLowercase } && (3...12).contains($0.count) })
}

@Test func defaultOptionsAreStrong() {
    #expect(PasswordGenerator.entropy(PasswordGenerator.CharacterOptions()) > 100)
    #expect(PasswordGenerator.entropy(PasswordGenerator.WordOptions()) > 50)
}

// MARK: - Biometric policy

@Test func biometricsNeedARecentPasswordUnlockInThisBoot() {
    let policy = BiometricPolicy(isEnabled: true)
    let unlock = DeviceClock(date: Date(timeIntervalSince1970: 1_000_000), bootSession: "boot-a", sinceBoot: 3_600)
    func later(_ seconds: TimeInterval, session: String? = "boot-a") -> DeviceClock {
        DeviceClock(date: unlock.date.addingTimeInterval(seconds), bootSession: session, sinceBoot: 3_600 + seconds)
    }

    #expect(policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: later(60)))
    #expect(policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: later(6 * 86_400)))
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: nil, now: later(60)))
    // Too long ago.
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: later(8 * 86_400)))
    // Restarted since: a new boot session.
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: later(60, session: "boot-b")))
    // Turned off.
    #expect(!BiometricPolicy(isEnabled: false).allowsBiometricUnlock(lastPasswordUnlock: unlock, now: later(60)))
}

@Test func settingTheClockBackDoesntReopenBiometrics() {
    let policy = BiometricPolicy(isEnabled: true)
    let unlock = DeviceClock(date: Date(timeIntervalSince1970: 1_000_000), bootSession: "boot-a", sinceBoot: 3_600)

    // After a restart, the date set back to just after the last password unlock.
    let restarted = DeviceClock(date: unlock.date.addingTimeInterval(60), bootSession: "boot-b", sinceBoot: 120)
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: restarted))
    // In the same boot, eight days later, with the date set back a week.
    let rewound = DeviceClock(
        date: unlock.date.addingTimeInterval(86_400), bootSession: "boot-a", sinceBoot: 3_600 + 8 * 86_400)
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: rewound))
    // A date before the unlock doesn't count either.
    let backwards = DeviceClock(date: unlock.date.addingTimeInterval(-60), bootSession: "boot-a", sinceBoot: 3_660)
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: backwards))
}

@Test func withoutABootSessionARestartComesFromTheBootTime() {
    let policy = BiometricPolicy(isEnabled: true)
    let unlock = DeviceClock(date: Date(timeIntervalSince1970: 1_000_000), bootSession: nil, sinceBoot: 3_600)

    let sameBoot = DeviceClock(date: unlock.date.addingTimeInterval(60), bootSession: nil, sinceBoot: 3_660)
    #expect(policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: sameBoot))
    // Started 30 seconds ago, after the unlock.
    let restarted = DeviceClock(date: unlock.date.addingTimeInterval(60), bootSession: nil, sinceBoot: 30)
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: unlock, now: restarted))
}

@Test func theCurrentClockHasABootSession() {
    let first = DeviceClock.current
    let second = DeviceClock.current
    #expect(first.bootSession != nil)
    #expect(first.bootSession == second.bootSession)
    #expect(second.sinceBoot >= first.sinceBoot)
    #expect(first.sinceBoot > 0)
}

@Test func touchIDCancelsAndFailuresFallBackToThePassword() {
    for code in [LAError.Code.userCancel, .appCancel, .systemCancel, .userFallback, .authenticationFailed] {
        #expect(BiometricKeychain.mapped(LAError(code)) as? BiometricError == .cancelled)
    }
    #expect(BiometricKeychain.mapped(LAError(.biometryNotEnrolled)) as? BiometricError == .unavailable)
    #expect(BiometricKeychain.mapped(LAError(.biometryLockout)) as? BiometricError == .lockedOut)
    #expect(BiometricKeychain.mapped(LAError(.invalidContext)) is LAError)
    #expect(BiometricKeychain.mapped(CryptoError.authenticationFailed) is CryptoError)
}

@Test func biometricErrorsReadAsSentences() {
    #expect(BiometricError.unavailable.localizedDescription == "Face ID or Touch ID isn't set up on this device.")
    let keychain = BiometricError.keychain(errSecInteractionNotAllowed).localizedDescription
    #expect(keychain.contains("(-25308)"))
    #expect(!keychain.contains("BiometricError"))
}

@Test(arguments: [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, -1, -2, -3, -4, -9])
func aFaceOrFingerThatIsNotRecognisedFallsBackQuietly(status: OSStatus) {
    #expect(BiometricKeychain.readFailure(status) == .cancelled)
}

@Test func otherKeychainFailuresAreReported() {
    #expect(BiometricKeychain.readFailure(-8) == .lockedOut)
    #expect(BiometricKeychain.readFailure(errSecMissingEntitlement) == .keychain(errSecMissingEntitlement))
}

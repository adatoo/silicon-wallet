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

@Test func biometricsNeedARecentPasswordUnlockSinceBoot() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let boot = now.addingTimeInterval(-3600)
    let policy = BiometricPolicy(isEnabled: true)

    #expect(policy.allowsBiometricUnlock(lastPasswordUnlock: now.addingTimeInterval(-60), bootTime: boot, now: now))
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: nil, bootTime: boot, now: now))
    // Restarted since the last password unlock.
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: boot.addingTimeInterval(-1), bootTime: boot, now: now))
    // Too long ago.
    let longBoot = now.addingTimeInterval(-30 * 86_400)
    #expect(
        !policy.allowsBiometricUnlock(
            lastPasswordUnlock: now.addingTimeInterval(-8 * 86_400), bootTime: longBoot, now: now))
    #expect(
        policy.allowsBiometricUnlock(
            lastPasswordUnlock: now.addingTimeInterval(-6 * 86_400), bootTime: longBoot, now: now))
    // A clock that has gone backwards doesn't count.
    #expect(!policy.allowsBiometricUnlock(lastPasswordUnlock: now.addingTimeInterval(60), bootTime: boot, now: now))
    // Turned off.
    #expect(!BiometricPolicy(isEnabled: false).allowsBiometricUnlock(lastPasswordUnlock: now, bootTime: boot, now: now))
}

@Test func bootTimeComesFromUptime() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(BiometricPolicy.bootTime(now: now, uptime: 400) == Date(timeIntervalSince1970: 9_600))
}

@Test func touchIDCancelsAndFailuresFallBackToThePassword() {
    for code in [LAError.Code.userCancel, .appCancel, .systemCancel, .userFallback, .authenticationFailed] {
        #expect(BiometricKeychain.mapped(LAError(code)) as? BiometricError == .cancelled)
    }
    #expect(BiometricKeychain.mapped(LAError(.biometryNotEnrolled)) as? BiometricError == .unavailable)
    #expect(BiometricKeychain.mapped(LAError(.biometryLockout)) is LAError)
    #expect(BiometricKeychain.mapped(CryptoError.authenticationFailed) is CryptoError)
}

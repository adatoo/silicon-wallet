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

// MARK: - Password reminder

@Test func thePasswordReminderIsDueOnceItsDateArrives() {
    let confirmed = Date(timeIntervalSince1970: 1_000_000)
    let next = PasswordReminder.next(afterConfirmingAt: confirmed)
    #expect(next == confirmed.addingTimeInterval(30 * 86_400))
    #expect(!PasswordReminder.isDue(next: next, now: next.addingTimeInterval(-1)))
    #expect(PasswordReminder.isDue(next: next, now: next))
    #expect(PasswordReminder.isDue(next: next, now: next.addingTimeInterval(86_400)))
}

@Test func notNowPutsTheReminderOffForAWeek() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let snoozed = PasswordReminder.next(afterSnoozingAt: now)
    #expect(snoozed == now.addingTimeInterval(7 * 86_400))
    #expect(snoozed < PasswordReminder.next(afterConfirmingAt: now))
}

@Test func withNoDateThePasswordReminderIsntDue() {
    #expect(!PasswordReminder.isDue(next: nil, now: .now))
}

// MARK: - Biometric errors

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

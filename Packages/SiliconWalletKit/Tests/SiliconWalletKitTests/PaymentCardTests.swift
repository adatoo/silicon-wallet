import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for card number checks. Every number is a published test number or made up to fit a
/// prefix; none is a real card.
@Test(arguments: [
    ("4111 1111 1111 1111", CardScheme.visa),
    ("4012888888881881", .visa),
    ("5555 5555 5555 4444", .mastercard),
    ("2223 0031 2200 3222", .mastercard),
    ("3782 822463 10005", .amex),
    ("371449635398431", .amex),
    ("6011 1111 1111 1117", .discover),
    ("6445 0000 0000 0000", .discover),
    ("3056 9309 0259 04", .diners),
    ("3852 0000 0232 37", .diners),
    ("3530 1113 3330 0000", .jcb),
    ("6200 0000 0000 0005", .unionPay),
    ("6759 6498 2643 8453", .maestro),
    ("5018 0000 0000 0009", .maestro),
])
func schemesAreRecognisedFromThePrefix(number: String, scheme: CardScheme) {
    #expect(PaymentCard.scheme(for: number) == scheme)
}

@Test func aPartNumberWaitsWhileAMoreSpecificSchemeCouldMatch() {
    #expect(PaymentCard.scheme(for: "4") == .visa)
    #expect(PaymentCard.scheme(for: "3") == nil)
    #expect(PaymentCard.scheme(for: "35") == nil)  // JCB needs 3528–3589
    #expect(PaymentCard.scheme(for: "3530") == .jcb)
    #expect(PaymentCard.scheme(for: "60") == nil)  // Discover 6011 or Maestro
    #expect(PaymentCard.scheme(for: "6011") == .discover)
    #expect(PaymentCard.scheme(for: "6012") == .maestro)
    #expect(PaymentCard.scheme(for: "22") == nil)
    #expect(PaymentCard.scheme(for: "2221") == .mastercard)
    #expect(PaymentCard.scheme(for: "2800") == nil)
    #expect(PaymentCard.scheme(for: "") == nil)
    #expect(PaymentCard.scheme(for: "not a number 4") == nil)
}

@Test func theLuhnCheckCatchesATypo() {
    #expect(PaymentCard.passesLuhn("4111111111111111"))
    #expect(PaymentCard.passesLuhn("378282246310005"))
    #expect(!PaymentCard.passesLuhn("4111111111111112"))
    #expect(!PaymentCard.passesLuhn("4111111111111"))
    #expect(!PaymentCard.passesLuhn("1"))
}

@Test func onlyAFullLengthNumberIsFlagged() {
    #expect(!PaymentCard.failsCheckDigit("4111 1111 1111 1111"))
    #expect(PaymentCard.failsCheckDigit("4111 1111 1111 1112"))
    #expect(!PaymentCard.failsCheckDigit("4111 1111 1111"))  // still typing
    #expect(PaymentCard.failsCheckDigit("3782 822463 10006"))  // Amex is complete at 15
    #expect(!PaymentCard.failsCheckDigit("Ask the bank"))
    #expect(!PaymentCard.failsCheckDigit(""))
}

@Test func numbersAreGroupedForReading() {
    #expect(PaymentCard.formatted("4111111111111111") == "4111 1111 1111 1111")
    #expect(PaymentCard.formatted("378282246310005") == "3782 822463 10005")
    #expect(PaymentCard.formatted("30569309025904") == "3056 930902 5904")
    #expect(PaymentCard.formatted("6759-6498-2643-8453-123") == "6759 6498 2643 8453 123")
    #expect(PaymentCard.formatted("n/a") == "n/a")
}

@Test func cardNumberFieldsAreFoundByLabel() {
    #expect(PaymentCard.isCardNumberLabel("Card Number"))
    #expect(PaymentCard.isCardNumberLabel("  card   number "))
    #expect(PaymentCard.isCardNumberLabel("Card No."))
    #expect(!PaymentCard.isCardNumberLabel("Account Number"))
    #expect(!PaymentCard.isCardNumberLabel("Card"))
}

@Test func anEntryKnowsItsCardScheme() {
    let number = FieldTemplate(label: "Card Number", kind: .number, isConcealed: true)
    let group = VaultGroup(name: "Fake Cards", fields: [FieldTemplate(label: "Cardholder"), number])
    let visa = VaultEntry(groupID: group.id, title: "Fake", values: [number.id: "4111 1111 1111 1111"])
    #expect(visa.cardScheme(in: group) == .visa)

    let extra = VaultEntry(
        groupID: UUID(), title: "Fake", extraFields: [CustomField(label: "card number", value: "5555555555554444")])
    #expect(extra.cardScheme(in: nil) == .mastercard)
    #expect(VaultEntry(groupID: group.id, title: "Fake").cardScheme(in: group) == nil)
}

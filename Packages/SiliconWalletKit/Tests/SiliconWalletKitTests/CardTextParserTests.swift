import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for reading card text. Every card is fake: published test numbers, made-up names.
@Test func theFrontOfACardIsRead() {
    let card = CardTextParser.front([
        "EXAMPLE BANK", "DEBIT", "4111 1111 1111 1111", "VALID FROM 01/24", "EXPIRES END 12/30", "JANE APPLESEED",
        "VISA",
    ])
    #expect(card == ScannedCard(number: "4111 1111 1111 1111", expiry: "12/30", cardholder: "JANE APPLESEED"))
}

@Test func aNumberSplitOverLinesOrMisreadIsStillFound() {
    #expect(CardTextParser.number(in: ["5555 5555", "5555 4444"]) == "5555 5555 5555 4444")
    #expect(CardTextParser.number(in: ["4111 1l11 1111 11I1"]) == "4111 1111 1111 1111")
    #expect(CardTextParser.number(in: ["51O5 1O51 0510 5100"]) == "5105 1051 0510 5100")
    #expect(CardTextParser.number(in: ["3782 822463 10005"]) == "3782 822463 10005")
    // Fails the check digit, so it isn't a number.
    #expect(CardTextParser.number(in: ["4111 1111 1111 1112"]) == nil)
    #expect(CardTextParser.number(in: ["Customer services 0345 300 0000"]) == nil)
    // A number on one line beats one made by joining lines.
    #expect(CardTextParser.number(in: ["4111 1111 1111 1111", "411"]) == "4111 1111 1111 1111")
}

@Test func expiryFormatsAreReadAndTheLatestWins() {
    #expect(CardTextParser.expiry(in: ["VALID THRU 09/2031"]) == "09/31")
    #expect(CardTextParser.expiry(in: ["GOOD THRU 03-29"]) == "03/29")
    #expect(CardTextParser.expiry(in: ["FROM 01/24 END 12/30"]) == "12/30")
    #expect(CardTextParser.expiry(in: ["12/30", "01/24"]) == "12/30")
    #expect(CardTextParser.expiry(in: ["13/30", "00/30", "123/45"]) == nil)
}

@Test func theCardholderIsALineOfCapitalsThatIsntCardWording() {
    #expect(CardTextParser.cardholder(in: ["MR J APPLESEED"]) == "MR J APPLESEED")
    #expect(CardTextParser.cardholder(in: ["O'NEIL-SMITH JANE"]) == "O'NEIL-SMITH JANE")
    #expect(CardTextParser.cardholder(in: ["VALID THRU", "WORLD MASTERCARD", "EXAMPLE BANK PLC"]) == nil)
    #expect(CardTextParser.cardholder(in: ["Jane Appleseed"]) == nil)
    #expect(CardTextParser.cardholder(in: ["JANE"]) == nil)
    #expect(CardTextParser.cardholder(in: ["JANE APPLESEED 4111"]) == nil)
}

@Test func theBackSuggestsTheSecurityCode() {
    let number = "4111 1111 1111 1111"
    #expect(CardTextParser.back(["AUTHORISED SIGNATURE", "1111 123"], cardNumber: number).securityCode == "123")
    #expect(CardTextParser.back(["CVV", "456"], cardNumber: number).securityCode == "456")
    // Phone numbers aren't codes.
    #expect(CardTextParser.back(["Call 0345 300 0000", "+44 207 123 4567"], cardNumber: number).securityCode == nil)
    #expect(CardTextParser.back(["0800 123"], cardNumber: number).securityCode == nil)
    // A three-digit group after something other than the last four digits isn't taken.
    #expect(CardTextParser.back(["2222 789"], cardNumber: number).securityCode == nil)
    #expect(CardTextParser.back([], cardNumber: nil).isEmpty)
}

@Test func americanExpressHasItsCodeOnTheFront() {
    let card = CardTextParser.front(["AMERICAN EXPRESS", "1234", "3782 822463 10005", "12/30", "JANE APPLESEED"])
    #expect(card.number == "3782 822463 10005")
    #expect(card.securityCode == "1234")
    #expect(CardTextParser.front(["4111 1111 1111 1111", "1234"]).securityCode == nil)
}

@Test func cardFieldsAreFoundByLabel() {
    #expect(CardField(label: "Card Number") == .number)
    #expect(CardField(label: "Expiry") == .expiry)
    #expect(CardField(label: "Valid Thru") == .expiry)
    #expect(CardField(label: "Cardholder") == .cardholder)
    #expect(CardField(label: "Name on card") == .cardholder)
    #expect(CardField(label: "Security Code") == .securityCode)
    #expect(CardField(label: "CVV") == .securityCode)
    #expect(CardField(label: "PIN") == nil)
    #expect(CardField.securityCode.value(in: ScannedCard(securityCode: "123")) == "123")
}

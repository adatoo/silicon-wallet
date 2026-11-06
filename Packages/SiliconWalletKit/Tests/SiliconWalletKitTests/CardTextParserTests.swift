import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for reading card text. Every card is fake: published test numbers, made-up names.
@Test func theFrontOfACardIsRead() {
    let card = CardTextParser.front([
        "EXAMPLE BANK", "DEBIT", "4111 1111 1111 1111", "VALID FROM 01/24", "EXPIRES END 12/30", "JANE APPLESEED",
        "VISA",
    ])
    #expect(
        card
            == ScannedCard(
                number: "4111 1111 1111 1111", validFrom: "01/24", expiry: "12/30", cardholder: "JANE APPLESEED"))
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

@Test func eachValueIsTracedToTheLineItWasReadFrom() {
    let lines = ["EXAMPLE BANK", "4111 1111", "1111 1111", "VALID FROM 01/24  EXPIRES END 12/30", "JANE APPLESEED"]
    let card = CardTextParser.front(lines)
    #expect(card.number == "4111 1111 1111 1111")
    let sources = CardTextParser.sources(of: card, in: lines)
    #expect(sources == [1: .number, 2: .number, 3: .expiry, 4: .cardholder])

    let back = ["CUSTOMER SERVICES 0345 300 0000", "AUTHORISED SIGNATURE", "1111 123"]
    let code = CardTextParser.back(back, cardNumber: "4111 1111 1111 1111")
    #expect(CardTextParser.sources(of: code, in: back) == [2: .securityCode])
    #expect(CardTextParser.sources(of: ScannedCard(), in: back).isEmpty)
}

@Test func aLineCanBeReassignedToAnotherField() {
    #expect(CardTextParser.value(for: .number, fromLine: "4111 1111 1111 1112") == "4111 1111 1111 1112")
    #expect(CardTextParser.value(for: .number, fromLine: "1111 123") == nil)
    #expect(CardTextParser.value(for: .expiry, fromLine: "GOOD THRU 09/29") == "09/29")
    #expect(CardTextParser.value(for: .expiry, fromLine: "JANE APPLESEED") == nil)
    #expect(CardTextParser.value(for: .cardholder, fromLine: "  MR J APPLESEED ") == "MR J APPLESEED")
    #expect(CardTextParser.value(for: .cardholder, fromLine: "   ") == nil)
    #expect(CardTextParser.value(for: .securityCode, fromLine: "1111 123") == "123")
    #expect(CardTextParser.value(for: .securityCode, fromLine: "CID 1234") == "1234")
    #expect(CardTextParser.value(for: .securityCode, fromLine: "NO DIGITS") == nil)

    var card = ScannedCard(number: "4111 1111 1111 1111")
    card[.expiry] = "09/29"
    card[.number] = nil
    #expect(card == ScannedCard(expiry: "09/29"))
    #expect(card[.expiry] == "09/29")
}

// MARK: - Valid From (#154)

@Test func aCardWithTwoDatesGivesItsStartAndItsExpiry() {
    let card = CardTextParser.front(["4111 1111 1111 1111", "VALID FROM 01/22", "EXPIRES END 12/27"])
    #expect(card.validFrom == "01/22")
    #expect(card.expiry == "12/27")
    let oneLine = CardTextParser.front(["4111 1111 1111 1111", "01/2022 12/2027"])
    #expect(oneLine.validFrom == "01/22")
    #expect(oneLine.expiry == "12/27")
}

@Test func oneDateIsTheExpiryUnlessItsLineSaysItsAStart() {
    #expect(CardTextParser.dates(in: ["12/27"]) == (nil, "12/27"))
    #expect(CardTextParser.dates(in: ["VALID THRU 12/27"]) == (nil, "12/27"))
    #expect(CardTextParser.dates(in: ["VALID FROM 01/22"]) == ("01/22", nil))
    #expect(CardTextParser.dates(in: ["MEMBER SINCE 05/19"]) == ("05/19", nil))
    // The same date twice is still one date.
    #expect(CardTextParser.dates(in: ["12/27", "EXPIRES 12/27"]) == (nil, "12/27"))
    #expect(CardTextParser.dates(in: ["EXAMPLE BANK"]) == (nil, nil))
}

@Test func theStartDateIsBoxedAndCanBeChosen() {
    let lines = ["4111 1111 1111 1111", "VALID FROM 01/22", "EXPIRES END 12/27"]
    let card = CardTextParser.front(lines)
    let sources = CardTextParser.sources(of: card, in: lines)
    #expect(sources[1] == .validFrom)
    #expect(sources[2] == .expiry)
    #expect(CardTextParser.value(for: .validFrom, fromLine: "FROM 01/22 END 12/27") == "01/22")
    #expect(CardTextParser.value(for: .expiry, fromLine: "FROM 01/22 END 12/27") == "12/27")
    #expect(CardField(label: "Valid From") == .validFrom)
    #expect(CardField(label: "Start Date") == .validFrom)
    #expect(ScannedCard(validFrom: "01/22").isEmpty == false)
}

@Test func liveReadingsMergeIntoTheEarliestStartAndLatestExpiry() {
    // A frame that read only the start took it for the expiry; the next read both.
    let first = ScannedCard(expiry: "01/22")
    let merged = first.merged(with: ScannedCard(validFrom: "01/22", expiry: "12/27"))
    #expect(merged.validFrom == "01/22")
    #expect(merged.expiry == "12/27")
    // A start that isn't before the expiry is dropped.
    #expect(ScannedCard(validFrom: "12/27").merged(with: ScannedCard(expiry: "12/27")).validFrom == nil)
    #expect(ScannedCard(number: "4111").merged(with: ScannedCard(number: "5555")).number == "4111")
}

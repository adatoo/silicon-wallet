import Foundation

/// What a card scan found. Every part is optional: many cards print the number on the back, or
/// not at all.
public struct ScannedCard: Equatable, Sendable {
    public var number: String?
    /// `MM/YY`.
    public var expiry: String?
    public var cardholder: String?
    /// Only from the back, and only a suggestion: the person confirms it (DESIGN.md §3).
    public var securityCode: String?

    public init(number: String? = nil, expiry: String? = nil, cardholder: String? = nil, securityCode: String? = nil) {
        self.number = number
        self.expiry = expiry
        self.cardholder = cardholder
        self.securityCode = securityCode
    }

    public var isEmpty: Bool { number == nil && expiry == nil && cardholder == nil && securityCode == nil }
}

/// The card fields a scan can fill, found by their labels.
public enum CardField: CaseIterable, Sendable {
    case number, expiry, cardholder, securityCode

    public init?(label: String) {
        let folded = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" }).joined(separator: " ")
        switch folded {
        case _ where PaymentCard.isCardNumberLabel(label): self = .number
        case "expiry", "expiry date", "expires", "expiration", "expiration date", "exp", "valid thru",
            "valid until":
            self = .expiry
        case "cardholder", "card holder", "cardholder name", "name on card", "name": self = .cardholder
        case "security code", "cvv", "cvc", "cvv2", "csc", "cid": self = .securityCode
        default: return nil
        }
    }

    public func value(in card: ScannedCard) -> String? {
        switch self {
        case .number: card.number
        case .expiry: card.expiry
        case .cardholder: card.cardholder
        case .securityCode: card.securityCode
        }
    }
}

/// Reads card details from text recognised on a card, line by line in reading order. Pure text
/// work: the camera and the recogniser are the app's.
public enum CardTextParser {
    /// The number, expiry and cardholder from the front of a card. American Express prints its
    /// four-digit security code on the front, so for one that's suggested too.
    public static func front(_ lines: [String]) -> ScannedCard {
        var card = ScannedCard()
        card.number = number(in: lines)
        card.expiry = expiry(in: lines)
        card.cardholder = cardholder(in: lines)
        if let number = card.number, PaymentCard.scheme(for: number) == .amex {
            card.securityCode = code(in: lines, length: 4, cardNumber: number)
        }
        return card
    }

    /// A suggested security code from the back of a card: a three-digit group that isn't part of
    /// a phone number or of the card number, which signature strips often print beside it.
    public static func back(_ lines: [String], cardNumber: String?) -> ScannedCard {
        var card = ScannedCard(securityCode: code(in: lines, length: 3, cardNumber: cardNumber))
        // Some cards print the number on the back.
        card.number = number(in: lines)
        return card
    }

    // MARK: - Number

    /// The longest run of digit groups that passes the Luhn check and has a known scheme and
    /// length, grouped for reading. Runs within one line come first; only if none fits are lines
    /// joined, for a number the recogniser split.
    static func number(in lines: [String]) -> String? {
        let perLine = lines.map(digitGroups)
        return perLine.lazy.compactMap(longestNumber).max { $0.count < $1.count }.map(PaymentCard.formatted)
            ?? longestNumber(perLine.flatMap { $0 }).map(PaymentCard.formatted)
    }

    private static func longestNumber(_ groups: [String]) -> String? {
        var best: String?
        for start in groups.indices {
            var digits = ""
            for group in groups[start...] {
                digits += group
                guard digits.count <= 19 else { break }
                if digits.count > (best?.count ?? 12), PaymentCard.passesLuhn(digits),
                    let scheme = PaymentCard.scheme(for: digits), scheme.lengths.contains(digits.count)
                {
                    best = digits
                }
            }
        }
        return best
    }

    /// The line's groups of digits, mending common recognition slips in groups that are mostly
    /// digits (O for 0, I or l for 1, S for 5, B for 8, Z for 2).
    static func digitGroups(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).compactMap { token in
            let digitCount = token.filter(\.isASCIIDigitCharacter).count
            guard digitCount * 2 >= token.count, digitCount > 0 else { return nil }
            let mended = String(token.map { slips[$0] ?? $0 })
            return mended.allSatisfy(\.isASCIIDigitCharacter) ? mended : nil
        }
    }

    private static let slips: [Character: Character] = [
        "O": "0", "o": "0", "D": "0", "I": "1", "l": "1", "|": "1", "S": "5", "B": "8", "Z": "2",
    ]

    // MARK: - Expiry

    /// The latest `MM/YY` or `MM/YYYY` date on the card, so "valid from" loses to "expires end".
    static func expiry(in lines: [String]) -> String? {
        let pattern = /(?:^|\D)(0[1-9]|1[0-2])\s?[\/\-.]\s?(\d{4}|\d{2})(?!\d)/
        var latest: (year: Int, month: Int)?
        for line in lines {
            for match in line.matches(of: pattern) {
                guard let month = Int(match.output.1), var year = Int(match.output.2) else { continue }
                if year < 100 { year += 2000 }
                guard (2000...2099).contains(year) else { continue }
                if latest.map({ (year, month) > ($0.year, $0.month) }) ?? true { latest = (year, month) }
            }
        }
        return latest.map { String(format: "%02d/%02d", $0.month, $0.year % 100) }
    }

    // MARK: - Cardholder

    /// The last line of two to four words in capital letters that isn't card wording, as printed.
    static func cardholder(in lines: [String]) -> String? {
        var found: String?
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            let words = text.split(separator: " ")
            guard (2...4).contains(words.count), (5...26).contains(text.count),
                text.allSatisfy({ $0.isUppercase || $0 == " " || $0 == "." || $0 == "'" || $0 == "-" }),
                words.contains(where: { $0.count >= 2 }),
                !words.contains(where: { cardWords.contains(String($0).trimmingCharacters(in: .punctuationCharacters)) }
                )
            else { continue }
            found = text
        }
        return found
    }

    private static let cardWords: Set<String> = [
        "VALID", "THRU", "FROM", "EXPIRES", "EXPIRY", "END", "GOOD", "MONTH", "YEAR", "DEBIT", "CREDIT",
        "BANK", "CARD", "VISA", "MASTERCARD", "PLATINUM", "GOLD", "SILVER", "BLACK", "CONTACTLESS", "MEMBER",
        "SINCE", "BUSINESS", "WORLD", "SIGNATURE", "ELECTRON", "CLASSIC", "REWARDS", "PREMIER", "AMERICAN",
        "EXPRESS", "MAESTRO", "PLC", "LTD", "LIMITED", "INFINITE", "ELITE", "CORPORATE", "PREPAID",
        "AUTHORISED", "AUTHORIZED", "NOT", "TRANSFERABLE", "CUSTOMER", "SERVICE", "ISSUED", "BY", "UK",
    ]

    // MARK: - Security code

    /// A group of exactly `length` digits standing alone, or after the card number's last four
    /// digits as on a signature strip. Groups in a run of ten or more digits, or one starting with
    /// 0 or +, look like a phone number and are skipped.
    static func code(in lines: [String], length: Int, cardNumber: String?) -> String? {
        let lastFour = cardNumber.flatMap(PaymentCard.digits(in:)).map { String($0.suffix(4)) }
        let numberGroups = Set(cardNumber.map { digitGroups($0) } ?? [])
        for line in lines {
            if line.contains("+") { continue }
            let groups = digitGroups(line)
            let total = groups.reduce(0) { $0 + $1.count }
            if total >= 10 || groups.first?.hasPrefix("0") == true && groups.count > 1 { continue }
            for (index, group) in groups.enumerated() where group.count == length {
                let before = index > 0 ? groups[index - 1] : nil
                let alone = groups.count == 1
                let afterLastFour = before != nil && before == lastFour && groups.count == 2
                if (alone || afterLastFour) && !numberGroups.contains(group) { return group }
            }
        }
        return nil
    }
}

extension Character {
    fileprivate var isASCIIDigitCharacter: Bool { asciiValue.map { (48...57).contains($0) } ?? false }
}

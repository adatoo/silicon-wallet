import Foundation

/// What a card scan found. Every part is optional: many cards print the number on the back, or
/// not at all.
public struct ScannedCard: Equatable, Sendable {
    public var number: String?
    /// `MM/YY`, the start date on a card that prints two dates.
    public var validFrom: String?
    /// `MM/YY`.
    public var expiry: String?
    public var cardholder: String?
    /// Only from the back, and only a suggestion: the person confirms it (DESIGN.md §3).
    public var securityCode: String?
    /// `12-34-56`, from a debit card that prints its account's details. It belongs to the bank
    /// account the card is related to, not the card (`BankDetails`).
    public var sortCode: String?
    /// Digits only, like the sort code the bank account's.
    public var accountNumber: String?

    public init(
        number: String? = nil, validFrom: String? = nil, expiry: String? = nil, cardholder: String? = nil,
        securityCode: String? = nil, sortCode: String? = nil, accountNumber: String? = nil
    ) {
        self.number = number
        self.validFrom = validFrom
        self.expiry = expiry
        self.cardholder = cardholder
        self.securityCode = securityCode
        self.sortCode = sortCode
        self.accountNumber = accountNumber
    }

    public var isEmpty: Bool { CardField.allCases.allSatisfy { $0.value(in: self) == nil } }

    /// One field's value, for a review that reassigns or clears it.
    public subscript(field: CardField) -> String? {
        get { field.value(in: self) }
        set {
            switch field {
            case .number: number = newValue
            case .validFrom: validFrom = newValue
            case .expiry: expiry = newValue
            case .cardholder: cardholder = newValue
            case .securityCode: securityCode = newValue
            case .sortCode: sortCode = newValue
            case .accountNumber: accountNumber = newValue
            }
        }
    }

    /// Keeps what this already has and adds what `other` found, for a live scan that sees a
    /// little more with each frame. The expiry is the later date and the start the earlier, and
    /// a start that isn't before the expiry is dropped: a frame that read only the start date
    /// took it for the expiry.
    public func merged(with other: ScannedCard) -> ScannedCard {
        let expiry = CardTextParser.later(expiry, other.expiry)
        var validFrom = CardTextParser.earlier(validFrom, other.validFrom)
        if let start = validFrom, let end = expiry, CardTextParser.order(start) >= CardTextParser.order(end) {
            validFrom = nil
        }
        return ScannedCard(
            number: number ?? other.number, validFrom: validFrom, expiry: expiry,
            cardholder: cardholder ?? other.cardholder, securityCode: securityCode ?? other.securityCode,
            sortCode: sortCode ?? other.sortCode, accountNumber: accountNumber ?? other.accountNumber)
    }
}

/// The card fields a scan can fill, found by their labels. The sort code and account number are
/// read from the card but belong to its bank account (`isBankAccount`).
public enum CardField: CaseIterable, Sendable {
    case number, validFrom, expiry, cardholder, securityCode, sortCode, accountNumber

    /// Whether the value goes to the card's related bank account rather than the card entry.
    public var isBankAccount: Bool { self == .sortCode || self == .accountNumber }

    public init?(label: String) {
        let folded = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" }).joined(separator: " ")
        switch folded {
        case _ where PaymentCard.isCardNumberLabel(label): self = .number
        case "expiry", "expiry date", "expires", "expiration", "expiration date", "exp", "valid thru",
            "valid until":
            self = .expiry
        case "valid from", "valid since", "from", "start", "start date", "issued", "issue date":
            self = .validFrom
        case "cardholder", "card holder", "cardholder name", "name on card", "name": self = .cardholder
        case "security code", "cvv", "cvc", "cvv2", "csc", "cid": self = .securityCode
        case _ where SortCode.isSortCodeLabel(label): self = .sortCode
        case "account number", "account no", "acc no", "account", "a/c number", "a/c no": self = .accountNumber
        default: return nil
        }
    }

    public func value(in card: ScannedCard) -> String? {
        switch self {
        case .number: card.number
        case .validFrom: card.validFrom
        case .expiry: card.expiry
        case .cardholder: card.cardholder
        case .securityCode: card.securityCode
        case .sortCode: card.sortCode
        case .accountNumber: card.accountNumber
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
        (card.validFrom, card.expiry) = dates(in: lines)
        card.cardholder = cardholder(in: lines)
        if let number = card.number, PaymentCard.scheme(for: number) == .amex {
            card.securityCode = code(in: lines, length: 4, cardNumber: number)
        }
        (card.sortCode, card.accountNumber) = bankDetails(in: lines, cardNumber: card.number)
        return card
    }

    /// A suggested security code from the back of a card: a three-digit group that isn't part of
    /// a phone number or of the card number, which signature strips often print beside it.
    public static func back(_ lines: [String], cardNumber: String?) -> ScannedCard {
        var card = ScannedCard(securityCode: code(in: lines, length: 3, cardNumber: cardNumber))
        // Some cards print the number on the back, and debit cards often the account's details.
        card.number = number(in: lines)
        (card.sortCode, card.accountNumber) = bankDetails(in: lines, cardNumber: card.number ?? cardNumber)
        return card
    }

    // MARK: - Where each value was read

    /// The line each found value was read from, by line index, so a review can box it. A line
    /// gives at most one field; a number split over lines marks each of its lines.
    public static func sources(of card: ScannedCard, in lines: [String]) -> [Int: CardField] {
        var found: [Int: CardField] = [:]
        let numberDigits = card.number.flatMap(PaymentCard.digits(in:))
        for (index, line) in lines.enumerated() {
            let groups = digitGroups(line)
            let digits = groups.joined()
            if let numberDigits, !digits.isEmpty, numberDigits.contains(digits),
                digits == numberDigits || digits.count >= 8
            {
                found[index] = .number
            } else if let expiry = card.expiry, Self.expiry(in: [line]) == expiry {
                found[index] = .expiry
            } else if let start = card.validFrom, Self.dateValues(in: line).contains(start) {
                found[index] = .validFrom
            } else if let sortCode = card.sortCode, digits == sortCode.filter(\.isASCIIDigitCharacter) {
                found[index] = .sortCode
            } else if let account = card.accountNumber, digits == account {
                found[index] = .accountNumber
            } else if let code = card.securityCode, groups.contains(code) {
                found[index] = .securityCode
            } else if let name = card.cardholder, line.trimmingCharacters(in: .whitespaces) == name {
                found[index] = .cardholder
            }
        }
        return found
    }

    /// What `line` gives as `field`, when the person says that's what it is; nil if it can't be.
    /// A number needs 12 to 19 digits but not a valid check digit (the editor warns about that).
    public static func value(for field: CardField, fromLine line: String) -> String? {
        let groups = digitGroups(line)
        switch field {
        case .number:
            let digits = groups.joined()
            return (12...19).contains(digits.count) ? PaymentCard.formatted(digits) : nil
        case .validFrom:
            return dateValues(in: line).min { order($0) < order($1) }
        case .expiry:
            return expiry(in: [line])
        case .cardholder:
            let text = line.trimmingCharacters(in: .whitespaces)
            return text.isEmpty || text.count > 40 ? nil : text
        case .securityCode:
            return groups.last { (3...4).contains($0.count) }
        case .sortCode:
            return SortCode.formatted(groups.joined())
        case .accountNumber:
            let digits = groups.joined()
            return (6...10).contains(digits.count) ? digits : nil
        }
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

    // MARK: - Dates

    /// The latest `MM/YY` or `MM/YYYY` date on the card, so "valid from" loses to "expires end".
    static func expiry(in lines: [String]) -> String? {
        lines.flatMap(dateValues(in:)).max { order($0) < order($1) }
    }

    /// The start and expiry dates. With two or more dates, the earliest is the start and the
    /// latest the expiry. One date is the expiry, unless its line says it's a start date and
    /// says nothing of an end.
    static func dates(in lines: [String]) -> (validFrom: String?, expiry: String?) {
        let found = lines.flatMap { line in dateValues(in: line).map { (date: $0, line: line) } }
        let distinct = Set(found.map(\.date))
        guard let latest = distinct.max(by: { order($0) < order($1) }) else { return (nil, nil) }
        if distinct.count > 1 { return (distinct.min { order($0) < order($1) }, latest) }
        let words = Set(
            found.flatMap { $0.line.uppercased().split(whereSeparator: { !$0.isLetter }).map(String.init) })
        if words.isDisjoint(with: endWords), !words.isDisjoint(with: startWords) { return (latest, nil) }
        return (nil, latest)
    }

    private static let startWords: Set<String> = ["FROM", "SINCE", "START", "STARTS", "ISSUED", "MEMBER"]
    private static let endWords: Set<String> = [
        "THRU", "THROUGH", "UNTIL", "TO", "EXP", "EXPIRES", "EXPIRY", "EXPIRATION", "END", "ENDS",
    ]

    /// Each valid `MM/YY` or `MM/YYYY` date in a line, as `MM/YY`.
    static func dateValues(in line: String) -> [String] {
        let pattern = /(?:^|\D)(0[1-9]|1[0-2])\s?[\/\-.]\s?(\d{4}|\d{2})(?!\d)/
        return line.matches(of: pattern).compactMap { match in
            guard let month = Int(match.output.1), var year = Int(match.output.2) else { return nil }
            if year < 100 { year += 2000 }
            guard (2000...2099).contains(year) else { return nil }
            return String(format: "%02d/%02d", month, year % 100)
        }
    }

    /// An `MM/YY` date as `YYMM`, which sorts by time.
    static func order(_ date: String) -> String { String(date.suffix(2)) + date.prefix(2) }

    static func later(_ a: String?, _ b: String?) -> String? {
        guard let a, let b else { return a ?? b }
        return order(b) > order(a) ? b : a
    }

    static func earlier(_ a: String?, _ b: String?) -> String? {
        guard let a, let b else { return a ?? b }
        return order(b) < order(a) ? b : a
    }

    // MARK: - Bank details

    /// A UK sort code and account number, as debit cards print them: on a line of their own,
    /// after their labels ("SORT CODE", "ACC NO") or on the line after one. Unlabelled, a sort
    /// code has to be written in pairs (`12-34-56`, `12 34 56`), and an account number is taken
    /// only as eight digits together beside a sort code. Lines with other text, such as a
    /// helpline, and digits from the card number, aren't taken.
    static func bankDetails(in lines: [String], cardNumber: String?) -> (sortCode: String?, accountNumber: String?) {
        let numberDigits = cardNumber.flatMap(PaymentCard.digits(in:)) ?? ""
        var sortCode: String?
        var account: String?
        var unlabelledAccount: String?
        var awaiting: CardField?
        for line in lines.map(latin) {
            let upper = line.uppercased()
            let words = upper.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let isAccount = words.contains("ACC") || words.contains("ACCOUNT") || upper.contains("A/C")
            let labelled: CardField? = words.contains("SORT") ? .sortCode : isAccount ? .accountNumber : nil
            let label = labelled ?? awaiting
            guard let value = bareDigits(line) else {
                // A label on its own line names the value on the next.
                awaiting = labelled.flatMap { words.allSatisfy(bankLabelWords.contains) ? $0 : nil }
                continue
            }
            awaiting = nil
            let digits = value.filter(\.isASCIIDigitCharacter)
            guard !digits.isEmpty, !numberDigits.contains(digits) else { continue }
            if sortCode == nil, digits.count == 6, label == .sortCode || isPaired(value) {
                sortCode = SortCode.formatted(digits)
            } else if account == nil, digits.count == 8, label == .accountNumber {
                account = digits
            } else if unlabelledAccount == nil, label == nil, digits.count == 8, value == digits {
                unlabelledAccount = digits
            }
        }
        return (sortCode, account ?? (sortCode == nil ? nil : unlabelledAccount))
    }

    /// The line with Cyrillic and Greek letters that look like Latin ones written as Latin: the
    /// recogniser sometimes reads the C in "ACC NO" as a Cyrillic С.
    static func latin(_ line: String) -> String {
        String(line.map { lookalikes[$0] ?? $0 })
    }

    private static let lookalikes: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T",
        "Х": "X", "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x", "Α": "A", "Β": "B", "Ε": "E",
        "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Χ": "X",
    ]

    private static let bankLabelWords: Set<String> = ["SORT", "CODE", "ACC", "ACCOUNT", "NO", "NUMBER", "A", "C"]

    /// The line's digits and separators once its bank labels are taken away, if that's all it
    /// has; nil if anything else is written on it.
    private static func bareDigits(_ line: String) -> String? {
        var rest = line.uppercased()
        for word in ["ACCOUNT", "NUMBER", "SORT", "CODE", "A/C", "ACC", "NO.", "NO", ":"] {
            rest = rest.replacingOccurrences(of: word, with: " ")
        }
        let value = rest.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCIIDigitCharacter || $0 == " " || $0 == "-" || $0 == "." })
        else { return nil }
        return value
    }

    /// Six digits written in pairs, `12-34-56` or `12 34 56`.
    private static func isPaired(_ value: String) -> Bool {
        value.wholeMatch(of: /\d{2}[ \-.]\d{2}[ \-.]\d{2}/) != nil
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

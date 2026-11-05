import Foundation

/// A payment card scheme, recognised from the number's issuer prefix (DESIGN.md §4).
public enum CardScheme: String, CaseIterable, Sendable {
    case visa, mastercard, amex, discover, diners, jcb, unionPay, maestro

    public var name: String {
        switch self {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "American Express"
        case .discover: "Discover"
        case .diners: "Diners Club"
        case .jcb: "JCB"
        case .unionPay: "UnionPay"
        case .maestro: "Maestro"
        }
    }

    /// The name as a badge shows it.
    public var badgeName: String {
        switch self {
        case .visa: "VISA"
        case .amex: "AMEX"
        case .diners: "Diners"
        default: name
        }
    }

    /// How many digits a full number has.
    public var lengths: Set<Int> {
        switch self {
        case .visa: [13, 16, 19]
        case .mastercard: [16]
        case .amex: [15]
        case .diners: Set(14...19)
        case .maestro: Set(12...19)
        case .discover, .jcb, .unionPay: Set(16...19)
        }
    }
}

/// Card number checks, worked out from a value whenever it's shown. Nothing here is stored.
public enum PaymentCard {
    /// The digits of `text`, ignoring spaces and dashes; nil if it holds anything else or no digit.
    public static func digits(in text: String) -> String? {
        var digits = ""
        for character in text {
            if let ascii = character.asciiValue, (48...57).contains(ascii) {
                digits.append(character)
            } else if !(character == " " || character == "-" || character == "\u{00A0}") {
                return nil
            }
        }
        return digits.isEmpty ? nil : digits
    }

    /// Whether `digits` passes the Luhn check digit (ISO/IEC 7812).
    public static func passesLuhn(_ digits: String) -> Bool {
        guard digits.count >= 2, digits.allSatisfy(\.isASCIIDigit) else { return false }
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            var digit = Int(String(character))!
            if offset.isMultiple(of: 2) == false {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum.isMultiple(of: 10)
    }

    /// The scheme of a full or partly typed number, or nil when it isn't known (yet). While a
    /// more specific prefix could still match, the answer waits for more digits.
    public static func scheme(for text: String) -> CardScheme? {
        guard let digits = digits(in: text) else { return nil }
        for rule in rules {
            if digits.count >= rule.width {
                if let prefix = Int(digits.prefix(rule.width)), rule.range.contains(prefix) { return rule.scheme }
            } else if let partial = Int(digits) {
                let scale = Int(pow(10, Double(rule.width - digits.count)))
                if (rule.range.lowerBound / scale...rule.range.upperBound / scale).contains(partial) { return nil }
            }
        }
        return nil
    }

    /// Whether a full-length number fails its check digit: a likely typo. False while it's still
    /// short, and for values that aren't card numbers.
    public static func failsCheckDigit(_ text: String) -> Bool {
        guard let digits = digits(in: text) else { return false }
        let isFullLength =
            scheme(for: digits).map { $0.lengths.contains(digits.count) } ?? (13...19).contains(digits.count)
        return isFullLength && !passesLuhn(digits)
    }

    /// The number grouped for reading: 4-6-5 for American Express, 4-6-4 for a 14-digit Diners
    /// Club, fours otherwise. Text that isn't a card number comes back unchanged.
    public static func formatted(_ text: String) -> String {
        guard let digits = digits(in: text) else { return text }
        let groups: [Int]
        switch (scheme(for: digits), digits.count) {
        case (.amex, 15): groups = [4, 6, 5]
        case (.diners, 14): groups = [4, 6, 4]
        default: groups = Array(repeating: 4, count: (digits.count + 3) / 4)
        }
        var parts: [Substring] = []
        var rest = Substring(digits)
        for size in groups where !rest.isEmpty {
            parts.append(rest.prefix(size))
            rest = rest.dropFirst(size)
        }
        return parts.joined(separator: " ")
    }

    /// Whether a field with this label holds a card number: "Card Number", as the starter Credit
    /// Cards group names it, ignoring case, accents and spacing, or "Card No".
    public static func isCardNumberLabel(_ label: String) -> Bool {
        let folded = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0 == "." }).joined(separator: " ")
        return folded == "card number" || folded == "card no"
    }

    private struct Rule {
        let scheme: CardScheme
        let range: ClosedRange<Int>
        /// How many leading digits `range` covers.
        let width: Int
    }

    /// Most specific first, so Maestro's wide range only catches what the others don't.
    private static let rules: [Rule] = [
        Rule(scheme: .amex, range: 34...34, width: 2),
        Rule(scheme: .amex, range: 37...37, width: 2),
        Rule(scheme: .jcb, range: 3528...3589, width: 4),
        Rule(scheme: .diners, range: 300...305, width: 3),
        Rule(scheme: .diners, range: 36...36, width: 2),
        Rule(scheme: .diners, range: 38...39, width: 2),
        Rule(scheme: .discover, range: 6011...6011, width: 4),
        Rule(scheme: .discover, range: 644...649, width: 3),
        Rule(scheme: .discover, range: 65...65, width: 2),
        Rule(scheme: .unionPay, range: 62...62, width: 2),
        Rule(scheme: .mastercard, range: 51...55, width: 2),
        Rule(scheme: .mastercard, range: 2221...2720, width: 4),
        Rule(scheme: .visa, range: 4...4, width: 1),
        Rule(scheme: .maestro, range: 50...50, width: 2),
        Rule(scheme: .maestro, range: 56...69, width: 2),
    ]
}

extension VaultEntry {
    /// The scheme of the first card number in this entry, in its group's fields or its extra
    /// fields, if it has one.
    public func cardScheme(in group: VaultGroup?) -> CardScheme? {
        for field in group?.fields ?? [] where PaymentCard.isCardNumberLabel(field.label) {
            if let value = values[field.id], let scheme = PaymentCard.scheme(for: value) { return scheme }
        }
        for field in extraFields where PaymentCard.isCardNumberLabel(field.label) {
            if let scheme = PaymentCard.scheme(for: field.value) { return scheme }
        }
        return nil
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { asciiValue.map { (48...57).contains($0) } ?? false }
}

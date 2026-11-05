import Foundation

/// UK bank sort codes, read as `12-34-56` (DESIGN.md §3).
public enum SortCode {
    /// Whether a field holds a sort code: "Sort Code", ignoring case, accents and the space or
    /// hyphen ("sortcode", "Sort-Code").
    public static func isSortCodeLabel(_ label: String) -> Bool {
        let folded = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "." }
        return folded == "sortcode"
    }

    /// `12-34-56` for exactly six digits, written with or without spaces, hyphens or dots between
    /// them; nil for anything else, which is left as written.
    public static func formatted(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy({ $0.isASCIIDigit || $0 == " " || $0 == "-" || $0 == "." }) else { return nil }
        let digits = trimmed.filter(\.isASCIIDigit)
        guard digits.count == 6, trimmed.first?.isASCIIDigit == true, trimmed.last?.isASCIIDigit == true else {
            return nil
        }
        let d = Array(digits)
        return "\(d[0])\(d[1])-\(d[2])\(d[3])-\(d[4])\(d[5])"
    }

    /// How a field's value reads: formatted when it's a sort code, as stored otherwise.
    public static func display(_ value: String, label: String) -> String {
        isSortCodeLabel(label) ? formatted(value) ?? value : value
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { asciiValue.map { (48...57).contains($0) } ?? false }
}

import Foundation

/// A rough strength estimate for the meter shown while choosing a password. It is guidance,
/// not a guarantee: it estimates entropy from the character classes used and the length, and
/// penalises repeats, runs and very common passwords.
public struct PasswordStrength: Equatable, Sendable {
    public enum Rating: Int, Comparable, Sendable, CaseIterable {
        case veryWeak, weak, fair, good, strong

        public static func < (a: Rating, b: Rating) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .veryWeak: "Very weak"
            case .weak: "Weak"
            case .fair: "Fair"
            case .good: "Good"
            case .strong: "Strong"
            }
        }
    }

    public let bits: Double
    public let rating: Rating

    private static let common: Set<String> = [
        "password", "password1", "123456", "12345678", "123456789", "1234567890", "qwerty", "qwertyuiop",
        "letmein", "welcome", "iloveyou", "admin", "abc123", "monkey", "dragon", "football", "sunshine",
        "princess", "trustno1", "passw0rd", "000000", "111111",
    ]

    public init(_ password: String) {
        let characters = Array(password)
        guard !characters.isEmpty else {
            bits = 0
            rating = .veryWeak
            return
        }

        var pool = 0
        if characters.contains(where: \.isLowercase) { pool += 26 }
        if characters.contains(where: \.isUppercase) { pool += 26 }
        if characters.contains(where: \.isNumber) { pool += 10 }
        if characters.contains(where: { $0.isASCII && !$0.isLetter && !$0.isNumber }) { pool += 33 }
        if characters.contains(where: { !$0.isASCII }) { pool += 100 }

        // Count only characters that add something: a repeat of the previous one, or the next
        // step of a run (abc, 123), counts for a quarter.
        var effective = 0.0
        for (index, character) in characters.enumerated() {
            if index > 0, Self.isRepeatOrStep(characters[index - 1], character) {
                effective += 0.25
            } else {
                effective += 1
            }
        }

        var bits = effective * log2(Double(max(pool, 2)))
        if Self.common.contains(password.lowercased()) { bits = min(bits, 10) }
        self.bits = bits
        rating =
            switch bits {
            case ..<28: .veryWeak
            case ..<40: .weak
            case ..<60: .fair
            case ..<80: .good
            default: .strong
            }
    }

    private static func isRepeatOrStep(_ a: Character, _ b: Character) -> Bool {
        guard let x = a.unicodeScalars.first?.value, let y = b.unicodeScalars.first?.value else { return false }
        return x == y || x + 1 == y || x == y + 1
    }
}

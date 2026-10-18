import Foundation

/// Generates passwords and passphrases with the system's cryptographically secure random
/// number generator (DESIGN.md §5).
public enum PasswordGenerator {
    public struct CharacterOptions: Codable, Equatable, Sendable {
        public var length: Int
        public var lowercase: Bool
        public var uppercase: Bool
        public var digits: Bool
        public var symbols: Bool
        /// Leaves out characters that are easy to misread: 0 O o 1 l I |.
        public var avoidAmbiguous: Bool

        public init(
            length: Int = 20, lowercase: Bool = true, uppercase: Bool = true, digits: Bool = true, symbols: Bool = true,
            avoidAmbiguous: Bool = true
        ) {
            self.length = length
            self.lowercase = lowercase
            self.uppercase = uppercase
            self.digits = digits
            self.symbols = symbols
            self.avoidAmbiguous = avoidAmbiguous
        }

        public static let lengthRange = 8...64
    }

    public struct WordOptions: Codable, Equatable, Sendable {
        public var wordCount: Int
        public var separator: String
        public var capitalise: Bool
        /// Adds one random digit to the end of one random word.
        public var includeDigit: Bool

        public init(wordCount: Int = 6, separator: String = "-", capitalise: Bool = true, includeDigit: Bool = true) {
            self.wordCount = wordCount
            self.separator = separator
            self.capitalise = capitalise
            self.includeDigit = includeDigit
        }

        public static let wordCountRange = 3...12
    }

    static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let digits = Array("0123456789")
    static let symbols = Array("!#$%&*+-=?@^_~.:;,/()[]{}")
    static let ambiguous = Set("0Oo1lI|")

    static func sets(_ options: CharacterOptions) -> [[Character]] {
        var sets: [[Character]] = []
        if options.lowercase { sets.append(lowercase) }
        if options.uppercase { sets.append(uppercase) }
        if options.digits { sets.append(digits) }
        if options.symbols { sets.append(symbols) }
        if sets.isEmpty { sets.append(lowercase) }
        if options.avoidAmbiguous { sets = sets.map { $0.filter { !ambiguous.contains($0) } } }
        return sets
    }

    /// A random password with at least one character from each chosen set.
    public static func password(_ options: CharacterOptions = CharacterOptions()) -> String {
        var rng = SystemRandomNumberGenerator()
        let sets = sets(options)
        let length = min(max(options.length, CharacterOptions.lengthRange.lowerBound, sets.count), 256)
        let pool = sets.flatMap { $0 }

        var characters = sets.map { $0.randomElement(using: &rng)! }
        while characters.count < length {
            characters.append(pool.randomElement(using: &rng)!)
        }
        characters.shuffle(using: &rng)
        return String(characters)
    }

    /// A passphrase of random words from `Wordlist`.
    public static func passphrase(_ options: WordOptions = WordOptions()) -> String {
        var rng = SystemRandomNumberGenerator()
        let count = min(max(options.wordCount, WordOptions.wordCountRange.lowerBound), 64)
        var words = (0..<count).map { _ in Wordlist.words.randomElement(using: &rng)! }
        if options.capitalise { words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        if options.includeDigit {
            let index = Int.random(in: 0..<words.count, using: &rng)
            words[index] += String(digits.randomElement(using: &rng)!)
        }
        return words.joined(separator: options.separator)
    }

    /// The entropy, in bits, of passwords made with these options.
    public static func entropy(_ options: CharacterOptions) -> Double {
        Double(max(options.length, CharacterOptions.lengthRange.lowerBound))
            * log2(Double(sets(options).joined().count))
    }

    public static func entropy(_ options: WordOptions) -> Double {
        var bits =
            Double(max(options.wordCount, WordOptions.wordCountRange.lowerBound)) * log2(Double(Wordlist.words.count))
        if options.includeDigit { bits += log2(10) + log2(Double(options.wordCount)) }
        return bits
    }
}

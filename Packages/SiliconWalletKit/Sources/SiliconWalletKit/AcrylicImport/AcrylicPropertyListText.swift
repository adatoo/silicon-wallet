/// Parses the old-style (NeXT/OpenStep) property-list text Wallet uses for an entry's
/// `infodictionary` column: a flat sequence of `"key" = "value";` pairs, one per line, with
/// `\\` and `\"` escapes inside quoted strings. Not a general plist parser: Wallet's own
/// values are always flat string-to-string maps in every fixture seen so far.
enum AcrylicPropertyListText {
    static func parseFlatStringDictionary(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var chars = Substring(text)[...]

        while let key = nextQuotedString(&chars) {
            skipWhitespace(&chars)
            guard chars.first == "=" else { break }
            chars.removeFirst()
            skipWhitespace(&chars)
            guard let value = nextQuotedString(&chars) else { break }
            result[key] = value
            skipWhitespace(&chars)
            if chars.first == ";" {
                chars.removeFirst()
            }
            skipWhitespace(&chars)
        }
        return result
    }

    /// Every quoted string after the first `=`: the items of Wallet's `"array" = ( "…", … );`
    /// text, used for an entry's attachment list.
    static func quotedStrings(afterEqualsIn text: String) -> [String] {
        guard let equals = text.firstIndex(of: "=") else { return [] }
        var chars = text[text.index(after: equals)...]
        var result: [String] = []
        while let open = chars.firstIndex(of: "\"") {
            chars = chars[open...]
            guard let value = nextQuotedString(&chars) else { break }
            result.append(value)
        }
        return result
    }

    private static func skipWhitespace(_ chars: inout Substring) {
        while let first = chars.first, first.isWhitespace {
            chars.removeFirst()
        }
    }

    private static func nextQuotedString(_ chars: inout Substring) -> String? {
        skipWhitespace(&chars)
        guard chars.first == "\"" else { return nil }
        chars.removeFirst()

        var value = ""
        while let char = chars.first {
            chars.removeFirst()
            if char == "\\", let escaped = chars.first {
                chars.removeFirst()
                value.append(escaped)
            } else if char == "\"" {
                return value
            } else {
                value.append(char)
            }
        }
        return value
    }
}

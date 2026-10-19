import SiliconWalletKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

extension FieldKind {
    var displayName: String {
        switch self {
        case .text: "Text"
        case .password: "Password"
        case .number: "Number"
        case .date: "Date"
        case .url: "Web Address"
        case .email: "Email"
        case .phone: "Phone"
        case .multiline: "Long Text"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .password: "key"
        case .number: "number"
        case .date: "calendar"
        case .url: "link"
        case .email: "envelope"
        case .phone: "phone"
        case .multiline: "text.alignleft"
        }
    }

    /// A link for the value, for kinds that can be opened.
    func link(for value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch self {
        case .url:
            if let url = URL(string: trimmed), url.scheme != nil { return url }
            return URL(string: "https://\(trimmed)")
        case .email:
            return URL(string: "mailto:\(trimmed)")
        case .phone:
            let digits = trimmed.filter { $0.isNumber || $0 == "+" }
            return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
        default:
            return nil
        }
    }
}

extension View {
    /// The keyboard and text behaviour that suits a field's kind.
    @ViewBuilder
    func fieldInput(_ kind: FieldKind) -> some View {
        #if os(iOS)
            switch kind {
            case .number:
                self.keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
            case .url:
                self.keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            case .email:
                self.keyboardType(.emailAddress).autocorrectionDisabled().textInputAutocapitalization(.never)
            case .phone:
                self.keyboardType(.phonePad)
            case .password:
                self.autocorrectionDisabled().textInputAutocapitalization(.never)
            case .text, .date, .multiline:
                self.autocorrectionDisabled()
            }
        #else
            self.autocorrectionDisabled()
        #endif
    }
}

extension View {
    /// Makes Return add a line in a multi-line text field on the Mac, where it would otherwise end
    /// editing. iOS already adds a line. Return with a modifier, such as Option, is left alone.
    @ViewBuilder
    func returnAddsLine() -> some View {
        #if os(macOS)
            onKeyPress(keys: [.return]) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                // The focused field's text view inserts the line at the cursor.
                let inserted =
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), with: nil) ?? false
                return inserted ? .handled : .ignored
            }
        #else
            self
        #endif
    }
}

/// SF Symbols offered for groups.
enum GroupIcons {
    static let all = [
        "folder", "person.badge.key", "key", "lock", "creditcard", "building.columns", "banknote", "cart",
        "bag", "globe", "envelope", "phone", "wifi", "server.rack", "desktopcomputer", "laptopcomputer",
        "iphone", "gamecontroller", "tv", "car", "airplane", "house", "heart", "cross.case", "pills",
        "graduationcap", "briefcase", "doc.text", "note.text", "person.text.rectangle", "person.2",
        "shield", "star", "gift", "music.note", "camera", "cloud", "bolt", "leaf", "pawprint",
    ]
}

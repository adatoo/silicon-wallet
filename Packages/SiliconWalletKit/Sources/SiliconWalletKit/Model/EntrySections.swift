import Foundation

/// Entries filed under one letter, for the A–Z sections in the entry list (DESIGN.md §3).
public struct EntrySection: Identifiable, Equatable, Sendable {
    /// Where titles that don't start with a letter go.
    public static let other = "#"

    public var letter: String
    public var entries: [VaultEntry]

    public var id: String { letter }

    public init(letter: String, entries: [VaultEntry]) {
        self.letter = letter
        self.entries = entries
    }
}

extension VaultEntry {
    /// The letter this entry is filed under: the title's first letter, without accents and in
    /// capitals, skipping leading spaces and punctuation. Titles that start with a digit or have
    /// no letter go under "#".
    public var indexLetter: String {
        guard let first = title.first(where: { $0.isLetter || $0.isNumber }), first.isLetter else {
            return EntrySection.other
        }
        let folded = String(first).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.uppercased().first.map(String.init) ?? EntrySection.other
    }
}

extension Array where Element == VaultEntry {
    /// The entries in A–Z sections, with "#" last. Entries keep their order within a section.
    public func sectionedByFirstLetter() -> [EntrySection] {
        let byLetter = Dictionary(grouping: self, by: \.indexLetter)
        let letters = byLetter.keys
            .filter { $0 != EntrySection.other }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let ordered = byLetter[EntrySection.other] == nil ? letters : letters + [EntrySection.other]
        return ordered.map { EntrySection(letter: $0, entries: byLetter[$0] ?? []) }
    }
}

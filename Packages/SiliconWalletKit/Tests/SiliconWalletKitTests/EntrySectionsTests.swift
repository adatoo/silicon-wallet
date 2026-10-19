import Foundation
import Testing

@testable import SiliconWalletKit

private let groupID = UUID()

private func entries(_ titles: [String]) -> [VaultEntry] {
    titles.map { VaultEntry(groupID: groupID, title: $0) }
}

@Test(arguments: [
    ("Fake Bank", "F"),
    ("fake mail", "F"),
    ("Éclair Fake", "E"),
    ("  'Quoted Fake'", "Q"),
    ("ßfake", "S"),
    ("Жфейк", "Ж"),
    ("4G Fake Router", "#"),
    ("", "#"),
    ("!!!", "#"),
])
func entriesAreFiledUnderTheirFirstLetter(title: String, letter: String) {
    #expect(VaultEntry(groupID: groupID, title: title).indexLetter == letter)
}

@Test func sectionsRunAToZWithOtherLast() {
    let sections = entries(["4G Fake", "Beta Fake", "alpha fake", "Éclair Fake", "Ångström Fake", "Zed Fake"])
        .sectionedByFirstLetter()
    #expect(sections.map(\.letter) == ["A", "B", "E", "Z", "#"])
    #expect(sections.first?.entries.map(\.title) == ["alpha fake", "Ångström Fake"])
}

@Test func entriesKeepTheirOrderWithinASection() {
    let sections = entries(["Fake C", "Fake A", "fake b"]).sectionedByFirstLetter()
    #expect(sections.map(\.letter) == ["F"])
    #expect(sections.first?.entries.map(\.title) == ["Fake C", "Fake A", "fake b"])
}

@Test func noEntriesMeansNoSections() {
    #expect([VaultEntry]().sectionedByFirstLetter().isEmpty)
}

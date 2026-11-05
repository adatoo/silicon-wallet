import Foundation
import Testing

@testable import SiliconWalletKit

private func fakeAttachment(_ name: String) -> AttachmentRef {
    AttachmentRef(filename: name, uti: "public.data", size: 1, fileKey: Data(count: 32), sha256: Data(count: 32))
}

private let original = VaultEntry(
    groupID: UUID(), title: "Fake",
    extraFields: [
        CustomField(label: "Fake PIN", kind: .password, value: "0000"),
        CustomField(label: "Empty"),
        CustomField(label: "Spaces", value: "  \n"),
        CustomField(label: "Fake Member", value: "FAKE-1"),
    ],
    attachments: [fakeAttachment("fake-a.pdf"), fakeAttachment("fake-b.png"), fakeAttachment("fake-c.txt")])

@Test func anUnchangedEntryRemovesNothing() {
    #expect(original.removals(since: original).isEmpty)
}

@Test func addingOrReorderingRemovesNothing() {
    var edited = original
    edited.attachments.reverse()
    edited.extraFields.reverse()
    edited.attachments.append(fakeAttachment("fake-new.pdf"))
    edited.extraFields.append(CustomField(label: "New", value: "fake"))
    #expect(edited.removals(since: original).isEmpty)
}

@Test func aRemovedAttachmentIsListed() {
    var edited = original
    edited.attachments.remove(at: 1)
    let removals = edited.removals(since: original)
    #expect(removals.attachments.map(\.filename) == ["fake-b.png"])
    #expect(removals.extraFields.isEmpty)
}

@Test func onlyRemovedFieldsWithAValueAreListed() {
    var edited = original
    edited.extraFields.removeAll { ["Fake PIN", "Empty", "Spaces"].contains($0.label) }
    #expect(edited.removals(since: original).extraFields.map(\.label) == ["Fake PIN"])
}

@Test func aClearedValueIsAnEditNotARemoval() {
    var edited = original
    edited.extraFields[0].value = ""
    #expect(edited.removals(since: original).isEmpty)
}

@Test func removalsKeepTheEntrysOrder() {
    var edited = original
    edited.extraFields = [original.extraFields[1]]
    edited.attachments = [original.attachments[1]]
    let removals = edited.removals(since: original)
    #expect(removals.extraFields.map(\.label) == ["Fake PIN", "Fake Member"])
    #expect(removals.attachments.map(\.filename) == ["fake-a.pdf", "fake-c.txt"])
}

// Moving to another group: an extra field whose label matches one of the new group's fields
// moves into it (`moved(from:to:)`), so it isn't a removal.

private let fakeOldGroup = VaultGroup(name: "Fake Custom Cards", fields: [FieldTemplate(label: "Card Number")])
private let fakeNewGroup = VaultGroup(
    name: "Fake Cards",
    fields: [FieldTemplate(label: "Card Number"), FieldTemplate(label: "pin ", kind: .number, isConcealed: true)])
private let fakeCard = VaultEntry(
    groupID: fakeOldGroup.id, title: "Fake Card", values: [fakeOldGroup.fields[0].id: "0000 0000 0000 0000"],
    extraFields: [
        CustomField(label: "PIN", kind: .number, isConcealed: true, value: "0000"),
        CustomField(label: "Fake Member", value: "FAKE-1"),
    ])

@Test func aFieldMovedIntoTheNewGroupsFieldIsNotARemoval() {
    let moved = fakeCard.moved(from: fakeOldGroup, to: fakeNewGroup)
    #expect(moved.values[fakeNewGroup.fields[1].id] == "0000")
    #expect(moved.removals(since: fakeCard, in: fakeNewGroup).isEmpty)
}

@Test func aFieldRemovedAfterMovingIsStillListed() {
    var moved = fakeCard.moved(from: fakeOldGroup, to: fakeNewGroup)
    moved.extraFields.removeAll { $0.label == "Fake Member" }
    #expect(moved.removals(since: fakeCard, in: fakeNewGroup).extraFields.map(\.label) == ["Fake Member"])
}

@Test func aMovedFieldClearedInItsNewPlaceIsListed() {
    var moved = fakeCard.moved(from: fakeOldGroup, to: fakeNewGroup)
    moved.values[fakeNewGroup.fields[1].id] = nil
    #expect(moved.removals(since: fakeCard, in: fakeNewGroup).extraFields.map(\.label) == ["PIN"])
}

@Test func withoutTheGroupAMovedFieldCountsAsRemoved() {
    let moved = fakeCard.moved(from: fakeOldGroup, to: fakeNewGroup)
    #expect(moved.removals(since: fakeCard).extraFields.map(\.label) == ["PIN"])
}

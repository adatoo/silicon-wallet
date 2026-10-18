import Foundation
import Testing

@testable import SiliconWalletKit

@Test func movingAnEntryKeepsEveryValue() {
    let old = VaultGroup(
        name: "Fake Old",
        fields: [
            FieldTemplate(label: "Username"),
            FieldTemplate(label: "Password", kind: .password),
            FieldTemplate(label: "Member Number"),
            FieldTemplate(label: "Empty"),
        ])
    let new = VaultGroup(
        name: "Fake New",
        fields: [
            FieldTemplate(label: "password", kind: .password),
            FieldTemplate(label: "Website", kind: .url),
            FieldTemplate(label: "Support Phone", kind: .phone),
        ])
    let entry = VaultEntry(
        groupID: old.id, title: "Fake",
        values: [old.fields[0].id: "fake.user", old.fields[1].id: "fake-pass", old.fields[2].id: "FAKE-1"],
        extraFields: [CustomField(label: "Support Phone", kind: .phone, value: "+44 20 0000 0000")])

    let moved = entry.moved(from: old, to: new)

    #expect(moved.groupID == new.id)
    #expect(moved.values == [new.fields[0].id: "fake-pass", new.fields[2].id: "+44 20 0000 0000"])
    #expect(moved.extraFields.map(\.label) == ["Username", "Member Number"])
    #expect(moved.extraFields.map(\.value) == ["fake.user", "FAKE-1"])
    #expect(moved.title == entry.title && moved.id == entry.id)
}

@Test func movingConcealedValuesKeepsThemConcealed() {
    let old = VaultGroup(name: "Fake Old", fields: [FieldTemplate(label: "PIN", kind: .number, isConcealed: true)])
    let new = VaultGroup(name: "Fake New")
    let entry = VaultEntry(groupID: old.id, title: "Fake", values: [old.fields[0].id: "0000"])

    let moved = entry.moved(from: old, to: new)
    #expect(moved.extraFields.first?.isConcealed == true)
    #expect(moved.extraFields.first?.kind == .number)
}

@Test func movingWithinTheSameGroupChangesNothing() {
    let group = VaultGroup(name: "Fake", fields: [FieldTemplate(label: "A")])
    let entry = VaultEntry(groupID: group.id, title: "Fake", values: [group.fields[0].id: "x"])
    #expect(entry.moved(from: group, to: group) == entry)
}

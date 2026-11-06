import Foundation
import Testing

@testable import SiliconWalletKit

/// A debit card's account details go to its bank account (#161). Every value is fake.
struct BankDetailsTests {
    private let group = VaultGroup(
        name: "Bank Accounts", icon: "building.columns",
        fields: [
            FieldTemplate(label: "Bank"), FieldTemplate(label: "Account Number", kind: .number, isConcealed: true),
            FieldTemplate(label: "Sort Code", kind: .number),
        ], order: 0)
    private var accountField: FieldTemplate { group.fields[1] }
    private var sortField: FieldTemplate { group.fields[2] }
    private let details = BankDetails(sortCode: "12-34-56", accountNumber: "12345678")

    @Test func onlyAScanWithDetailsHasAny() {
        #expect(BankDetails(card: ScannedCard(number: "4111 1111 1111 1111")) == nil)
        #expect(BankDetails(card: ScannedCard(sortCode: "12-34-56"))?.sortCode == "12-34-56")
        #expect(BankDetails.isBankAccountGroup(group))
        #expect(!BankDetails.isBankAccountGroup(VaultGroup(name: "Notes", icon: "note", fields: [], order: 1)))
    }

    @Test func theFitSaysWhetherAnythingWouldBeReplaced() {
        let empty = VaultEntry(groupID: group.id, title: "Example Bank")
        #expect(details.fit(empty, in: group) == .fills)
        let same = VaultEntry(
            groupID: group.id, title: "Example Bank", values: [sortField.id: "123456", accountField.id: "12345678"])
        #expect(details.fit(same, in: group) == .same)
        let half = VaultEntry(groupID: group.id, title: "Example Bank", values: [sortField.id: "12-34-56"])
        #expect(details.fit(half, in: group) == .fills)
        let other = VaultEntry(groupID: group.id, title: "Example Bank", values: [accountField.id: "87654321"])
        #expect(details.fit(other, in: group) == .differs)
    }

    @Test func theyGoIntoTheAccountsFieldsOrNewExtraOnes() {
        let filled = details.applied(to: VaultEntry(groupID: group.id, title: "Example Bank"), in: group)
        #expect(filled.values[sortField.id] == "12-34-56")
        #expect(filled.values[accountField.id] == "12345678")
        #expect(filled.extraFields.isEmpty)
        let bare = VaultGroup(name: "Accounts", icon: "building.columns", fields: [], order: 2)
        let extra = details.newAccount(in: bare, title: "Example Bank Account")
        #expect(extra.title == "Example Bank Account")
        #expect(extra.extraFields.map(\.label) == ["Sort Code", "Account Number"])
        #expect(extra.extraFields[1].isConcealed)
    }
}

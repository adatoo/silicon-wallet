import Testing

@testable import SiliconWalletKit

@Test func sortCodeLabelsAreFoundHoweverTheyAreWritten() {
    for label in ["Sort Code", "sort code", "SORTCODE", "Sort-Code", " Sort  Code "] {
        #expect(SortCode.isSortCodeLabel(label), "\(label)")
    }
    for label in ["Sort", "Code", "Account Number", "Sort Code 2", ""] {
        #expect(!SortCode.isSortCodeLabel(label), "\(label)")
    }
}

@Test func sixDigitsBecomeAHyphenatedSortCode() {
    #expect(SortCode.formatted("123456") == "12-34-56")
    #expect(SortCode.formatted("12 34 56") == "12-34-56")
    #expect(SortCode.formatted("12-34-56") == "12-34-56")
    #expect(SortCode.formatted("12.34.56") == "12-34-56")
    #expect(SortCode.formatted(" 123456 ") == "12-34-56")
    #expect(SortCode.formatted("1234-56") == "12-34-56")
}

@Test func anythingButSixDigitsIsLeftAlone() {
    for value in [
        "", "12345", "1234567", "12-34-5", "12-34-567", "AB-CD-EF", "12-34-5O", "-123456", "123456-",
        "12/34/56",
    ] {
        #expect(SortCode.formatted(value) == nil, "\(value)")
    }
}

@Test func onlySortCodeFieldsAreShownFormatted() {
    #expect(SortCode.display("123456", label: "Sort Code") == "12-34-56")
    #expect(SortCode.display("123456", label: "Account Number") == "123456")
    #expect(SortCode.display("not a code", label: "Sort Code") == "not a code")
}

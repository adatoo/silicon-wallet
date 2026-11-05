import SiliconWalletKit
import SwiftUI
import Testing

@testable import SiliconWallet

/// A fake card, drawn large and plain so the recogniser reads it as it would a good photo.
private struct FakeCard: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.system(size: 34, weight: .semibold, design: .monospaced))
        .foregroundStyle(.black)
        .padding(40)
        .frame(width: 860, height: 540, alignment: .leading)
        .background(.white)
    }
}

@MainActor
private func photo(of lines: [String]) throws -> CGImage {
    let renderer = ImageRenderer(content: FakeCard(lines: lines))
    renderer.scale = 1
    return try #require(renderer.cgImage)
}

@MainActor
@Test func aPhotoOfTheFrontIsReadOnTheDevice() async throws {
    let image = try photo(of: [
        "EXAMPLE BANK", "4111 1111 1111 1111", "VALID FROM 01/24  EXPIRES END 12/30", "JANE APPLESEED",
    ])
    let card = try await CardTextRecognizer.card(in: image, side: .front, cardNumber: nil)
    #expect(card.number == "4111 1111 1111 1111")
    #expect(card.expiry == "12/30")
    #expect(card.cardholder == "JANE APPLESEED")
    #expect(card.securityCode == nil)
}

@MainActor
@Test func aPhotoOfTheBackSuggestsTheSecurityCode() async throws {
    let image = try photo(of: ["CUSTOMER SERVICES 0345 300 0000", "AUTHORISED SIGNATURE", "1111 123"])
    let card = try await CardTextRecognizer.card(in: image, side: .back, cardNumber: "4111 1111 1111 1111")
    #expect(card.securityCode == "123")
}

@Test func aLiveScanKeepsWhatItFoundAndTheLaterDate() {
    let first = ScannedCard(number: "4111 1111 1111 1111", expiry: "01/24")
    let next = ScannedCard(number: nil, expiry: "12/30", cardholder: "JANE APPLESEED")
    #expect(
        first.merged(with: next)
            == ScannedCard(number: "4111 1111 1111 1111", expiry: "12/30", cardholder: "JANE APPLESEED"))
    #expect(next.merged(with: ScannedCard(expiry: "01/24")).expiry == "12/30")
}

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
    let card = try await CardImageAnalyzer.analyse(image, side: .front, cardNumber: nil, detail: .still).card
    #expect(card.number == "4111 1111 1111 1111")
    #expect(card.expiry == "12/30")
    #expect(card.cardholder == "JANE APPLESEED")
    #expect(card.securityCode == nil)
}

@MainActor
@Test func aPhotoOfTheBackSuggestsTheSecurityCode() async throws {
    let image = try photo(of: ["CUSTOMER SERVICES 0345 300 0000", "AUTHORISED SIGNATURE", "1111 123"])
    let card = try await CardImageAnalyzer.analyse(
        image, side: .back, cardNumber: "4111 1111 1111 1111", detail: .still
    ).card
    #expect(card.securityCode == "123")
}

/// A photo of a card lying a little crooked on a dark table, as Take Photo would send it.
@MainActor
private func photoOnATable(of lines: [String]) throws -> CGImage {
    let table = ZStack {
        Color(white: 0.18)
        FakeCard(lines: lines)
            .clipShape(.rect(cornerRadius: 36))
            .rotationEffect(.degrees(6))
    }
    .frame(width: 1400, height: 1100)
    let renderer = ImageRenderer(content: table)
    renderer.scale = 1
    return try #require(renderer.cgImage)
}

@MainActor
@Test func theCardIsFoundStraightenedAndItsTextBoxed() async throws {
    let image = try photoOnATable(of: [
        "EXAMPLE BANK", "4111 1111 1111 1111", "VALID FROM 01/24  EXPIRES END 12/30", "JANE APPLESEED",
    ])
    let analysis = try await CardImageAnalyzer.analyse(image, side: .front, cardNumber: nil, detail: .still)
    let quad = try #require(analysis.quad)
    #expect(quad.bounds.width > 0.5 && quad.bounds.width < 0.8)
    let straightened = try #require(analysis.image)
    let ratio = Double(straightened.width) / Double(straightened.height)
    #expect(abs(ratio - 860.0 / 540.0) < 0.12, "\(ratio)")
    #expect(analysis.card.number == "4111 1111 1111 1111")
    #expect(analysis.card.expiry == "12/30")
    let number = try #require(analysis.lines.first { $0.field == .number })
    #expect(number.text.contains("4111"))
    #expect(number.box.minX >= 0 && number.box.maxX <= 1 && number.box.minY >= 0 && number.box.maxY <= 1)
    #expect(analysis.lines.contains { $0.field == .cardholder })
}

@MainActor
@Test func withNoCardEdgeTheWholePhotoIsRead() async throws {
    let image = try photo(of: ["4111 1111 1111 1111", "EXPIRES 12/30"])
    let analysis = try await CardImageAnalyzer.analyse(image, side: .front, cardNumber: nil, detail: .still)
    #expect(analysis.card.number == "4111 1111 1111 1111")
    #expect(analysis.lines.contains { $0.field == .number })
}

@Test func aLiveScanKeepsWhatItFoundAndTheLaterDate() {
    let first = ScannedCard(number: "4111 1111 1111 1111", expiry: "01/24")
    let next = ScannedCard(number: nil, expiry: "12/30", cardholder: "JANE APPLESEED")
    #expect(
        first.merged(with: next)
            == ScannedCard(number: "4111 1111 1111 1111", expiry: "12/30", cardholder: "JANE APPLESEED"))
    #expect(next.merged(with: ScannedCard(expiry: "01/24")).expiry == "12/30")
}

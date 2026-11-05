import CoreGraphics
import SiliconWalletKit
import SwiftUI
import Vision

/// Which side of a card a scan reads (DESIGN.md §3, ADR-0009).
enum CardScanSide: String, Identifiable {
    case front, back
    var id: String { rawValue }
}

/// Reads the lines of text in a photo of a card, on this device, with Vision. The image is
/// only ever in memory, and nothing it reads is logged.
enum CardTextRecognizer {
    static func lines(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Names and numbers aren't words; correction would "fix" them.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image)
        // Top to bottom, then left to right. Vision's origin is the bottom left.
        let sorted = observations.sorted {
            let a = $0.boundingBox.origin
            let b = $1.boundingBox.origin
            return abs(a.y - b.y) > 0.02 ? a.y > b.y : a.x < b.x
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }

    /// The details on one side of a card, from a photo of it.
    static func card(in image: CGImage, side: CardScanSide, cardNumber: String?) async throws -> ScannedCard {
        let lines = try await lines(in: image)
        return side == .front ? CardTextParser.front(lines) : CardTextParser.back(lines, cardNumber: cardNumber)
    }
}

extension ScannedCard {
    /// Keeps what this already has and adds what `other` found, for a live scan that sees a
    /// little more with each frame.
    func merged(with other: ScannedCard) -> ScannedCard {
        ScannedCard(
            number: number ?? other.number, expiry: Self.later(expiry, other.expiry),
            cardholder: cardholder ?? other.cardholder, securityCode: securityCode ?? other.securityCode)
    }

    /// The later of two `MM/YY` dates, so a start date seen first gives way to the expiry.
    private static func later(_ a: String?, _ b: String?) -> String? {
        func key(_ date: String) -> String { String(date.suffix(2)) + date.prefix(2) }
        guard let a, let b else { return a ?? b }
        return key(b) > key(a) ? b : a
    }
}

/// What a scan found, for the person to check before using it.
struct ScannedCardSummary: View {
    let card: ScannedCard
    let side: CardScanSide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if card.isEmpty {
                Text(
                    side == .front ? "Looking for the card number, expiry and name…" : "Looking for the security code…"
                )
                .foregroundStyle(.secondary)
            }
            row("Card Number", card.number, monospaced: true)
            row("Expiry", card.expiry, monospaced: true)
            row("Cardholder", card.cardholder, monospaced: false)
            row("Security Code", card.securityCode, monospaced: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?, monospaced: Bool) -> some View {
        if let value {
            LabeledContent(label) {
                HStack(spacing: 6) {
                    if label == "Card Number", let scheme = PaymentCard.scheme(for: value) {
                        CardSchemeBadge(scheme: scheme)
                    }
                    Text(value).fontDesign(monospaced ? .monospaced : nil)
                }
            }
        }
    }
}

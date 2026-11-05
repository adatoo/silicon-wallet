import SiliconWalletKit
import SwiftUI

/// Which side of a card a scan reads (DESIGN.md §3, ADR-0009).
enum CardScanSide: String, Identifiable {
    case front, back
    var id: String { rawValue }
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

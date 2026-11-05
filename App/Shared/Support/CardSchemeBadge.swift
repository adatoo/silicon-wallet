import SiliconWalletKit
import SwiftUI

/// A card's scheme as a small coloured capsule with its name. Drawn by the app; the schemes'
/// own logos are their trademarks and aren't used (DESIGN.md §3).
struct CardSchemeBadge: View {
    let scheme: CardScheme

    var body: some View {
        Text(scheme.badgeName)
            .font(.caption2.weight(.heavy))
            .italic(scheme == .visa)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(scheme.colour, in: .capsule)
            .fixedSize()
            .help(scheme.name)
            .accessibilityLabel("Card scheme: \(scheme.name)")
    }
}

extension CardScheme {
    /// A colour in the spirit of the scheme's branding, dark enough for white text.
    fileprivate var colour: Color {
        switch self {
        case .visa: Color(red: 0.10, green: 0.12, blue: 0.44)
        case .mastercard: Color(red: 0.85, green: 0.22, blue: 0.05)
        case .amex: Color(red: 0.12, green: 0.42, blue: 0.70)
        case .discover: Color(red: 0.85, green: 0.38, blue: 0.0)
        case .diners: Color(red: 0.0, green: 0.40, blue: 0.65)
        case .jcb: Color(red: 0.05, green: 0.40, blue: 0.25)
        case .unionPay: Color(red: 0.75, green: 0.08, blue: 0.18)
        case .maestro: Color(red: 0.0, green: 0.45, blue: 0.70)
        }
    }
}

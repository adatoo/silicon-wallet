import SiliconWalletKit
import SwiftUI

/// The editor's scan buttons for a card entry (ADR-0009): a live camera scan, with the device's
/// camera or, on a Mac, a nearby iPhone. Each hands back what the person chose to use.
struct CardScanButtons: View {
    /// The number already in the entry, so a back scan can skip its last four digits.
    let cardNumber: String?
    let canScanBack: Bool
    let onScanned: (ScannedCard) -> Void
    @State private var side: CardScanSide?

    /// Whether this device can scan at all; the simulator, for one, can't. A Mac always can:
    /// with no camera, the scan offers a photo from a nearby iPhone instead.
    static var isAvailable: Bool {
        #if os(iOS)
            LiveCardScanSheet.isSupported
        #else
            true
        #endif
    }

    var body: some View {
        HStack(spacing: 16) {
            Button("Scan Card", systemImage: "camera.viewfinder") { side = .front }
            if canScanBack {
                Button("Scan Back", systemImage: "rectangle.and.pencil.and.ellipsis") { side = .back }
            }
        }
        .buttonStyle(.borderless)
        #if os(iOS)
            .fullScreenCover(item: $side) { side in
                LiveCardScanSheet(side: side, cardNumber: cardNumber, onUse: onScanned)
            }
        #else
            .sheet(item: $side) { side in
                LiveCardScanSheet(side: side, cardNumber: cardNumber, onUse: onScanned)
            }
        #endif
    }
}

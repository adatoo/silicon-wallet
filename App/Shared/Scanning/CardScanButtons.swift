import SiliconWalletKit
import SwiftUI

/// The editor's scan buttons for a card entry (ADR-0009): a live camera scan on iPhone and
/// iPad, and a photo from a nearby iPhone through Continuity Camera on the Mac. Each hands back
/// what the person chose to use.
struct CardScanButtons: View {
    /// The number already in the entry, so a back scan can skip its last four digits.
    let cardNumber: String?
    let canScanBack: Bool
    let onScanned: (ScannedCard) -> Void
    #if os(iOS)
        @State private var side: CardScanSide?
    #else
        @State private var photo: CardPhoto?
    #endif

    /// Whether this device can scan at all; the simulator, for one, can't.
    static var isAvailable: Bool {
        #if os(iOS)
            LiveCardScanSheet.isSupported
        #else
            true
        #endif
    }

    var body: some View {
        HStack(spacing: 16) {
            #if os(iOS)
                Button("Scan Card", systemImage: "camera.viewfinder") { side = .front }
                if canScanBack {
                    Button("Scan Back", systemImage: "rectangle.and.pencil.and.ellipsis") { side = .back }
                }
            #else
                ContinuityCameraButton(title: "Scan Card with iPhone…") { photo = CardPhoto(image: $0, side: .front) }
                    .fixedSize()
                if canScanBack {
                    ContinuityCameraButton(title: "Scan Back with iPhone…") {
                        photo = CardPhoto(image: $0, side: .back)
                    }
                    .fixedSize()
                }
            #endif
        }
        .buttonStyle(.borderless)
        #if os(iOS)
            .fullScreenCover(item: $side) { side in
                LiveCardScanSheet(side: side, cardNumber: cardNumber, onUse: onScanned)
            }
        #else
            .sheet(item: $photo) { photo in
                CardPhotoReviewSheet(photo: photo, cardNumber: cardNumber, onUse: onScanned)
            }
        #endif
    }
}

import SiliconWalletKit
import SwiftUI

/// A photo of a card, from Continuity Camera, waiting to be read.
struct CardPhoto: Identifiable {
    let id = UUID()
    let image: CGImage
    let side: CardScanSide
}

/// Reads a photo of a card on this Mac and shows what it found, for the person to check before
/// Use fills the entry (ADR-0009). The photo is dropped when the sheet closes.
struct CardPhotoReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photo: CardPhoto
    let cardNumber: String?
    let onUse: (ScannedCard) -> Void
    @State private var found: ScannedCard?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                if let found, !found.isEmpty {
                    Section {
                        ScannedCardSummary(card: found, side: photo.side)
                    } footer: {
                        Text("Check these before you use them.")
                    }
                } else if found != nil || failed {
                    ContentUnavailableView(
                        "Nothing Found", systemImage: "creditcard.trianglebadge.exclamationmark",
                        description: Text(
                            photo.side == .front
                                ? "Try again with the front of the card filling the photo, in good light."
                                : "Try again with the signature strip in the photo, in good light."))
                } else {
                    ProgressView("Reading the card…")
                        .frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(photo.side == .front ? "Card Details" : "Security Code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let found { onUse(found) }
                        dismiss()
                    }
                    .disabled(found?.isEmpty ?? true)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 280)
        .task {
            do {
                found = try await CardTextRecognizer.card(in: photo.image, side: photo.side, cardNumber: cardNumber)
            } catch {
                failed = true
            }
        }
    }
}

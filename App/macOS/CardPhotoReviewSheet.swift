import SiliconWalletKit
import SwiftUI

/// A photo of a card, from Continuity Camera, waiting to be read.
struct CardPhoto: Identifiable {
    let id = UUID()
    let image: CGImage
    let side: CardScanSide
}

/// Finds the card in a photo on this Mac, reads it, and shows what it found over the card for
/// the person to check and correct before Use fills the entry (ADR-0009). The photo is dropped
/// when the sheet closes.
struct CardPhotoReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photo: CardPhoto
    let cardNumber: String?
    let onUse: (ScannedCard) -> Void
    @State private var analysis: CardAnalysis?
    @State private var lines: [RecognisedLine] = []
    @State private var card = ScannedCard()
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let analysis {
                        CardScanReview(
                            image: analysis.image ?? photo.image, side: photo.side, lines: $lines, card: $card)
                        if card.isEmpty {
                            Text(
                                photo.side == .front
                                    ? "Nothing found yet. Choose text on the card, or try again with the front of the card filling the photo, in good light."
                                    : "Nothing found yet. Choose the code on the card, or try again with the signature strip in the photo, in good light."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                    } else if failed {
                        ContentUnavailableView(
                            "Couldn't Read the Photo", systemImage: "creditcard.trianglebadge.exclamationmark",
                            description: Text("Try taking it again."))
                    } else {
                        ProgressView("Reading the card…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .navigationTitle(photo.side == .front ? "Card Details" : "Security Code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(card)
                        dismiss()
                    }
                    .disabled(card.isEmpty)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .task {
            do {
                let found = try await CardImageAnalyzer.analyse(
                    photo.image, side: photo.side, cardNumber: cardNumber, detail: .still)
                analysis = found
                lines = found.lines
                card = found.card
            } catch {
                failed = true
            }
        }
    }
}

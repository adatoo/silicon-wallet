import SiliconWalletKit
import SwiftUI

/// Screenshots only (`-ScreenshotCardScan`): the card-scan review as it looks after a capture,
/// read on the device from a drawn example card, since a simulator has no camera. Uses the same
/// analyser and review as a real scan; nothing is saved.
struct ScreenshotCardScan: View {
    @State private var analysis: CardAnalysis?
    @State private var lines: [RecognisedLine] = []
    @State private var card = ScannedCard()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let analysis {
                    CardScanReview(image: analysis.image ?? Self.photo, lines: $lines, card: $card)
                        .padding()
                } else {
                    ProgressView().padding(40)
                }
            }
            .navigationTitle("Scan Card")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                ToolbarItem(placement: .confirmationAction) { Button("Use") {} }
                #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Button("Retake", systemImage: "arrow.counterclockwise") {}
                            .labelStyle(.titleAndIcon)
                    }
                #endif
            }
        }
        .task {
            guard
                let found = try? await CardImageAnalyzer.analyse(
                    Self.photo, side: .front, cardNumber: nil, detail: .still)
            else { return }
            analysis = found
            lines = found.lines
            card = found.card
        }
    }

    /// An obviously fake debit card on a dark table.
    @MainActor private static let photo: CGImage = {
        let renderer = ImageRenderer(content: CardOnTable())
        renderer.scale = 1
        return renderer.cgImage!
    }()
}

private struct CardOnTable: View {
    var body: some View {
        ZStack {
            Color(white: 0.16)
            ExampleCard()
                .rotationEffect(.degrees(-3))
        }
        .frame(width: 1400, height: 1000)
    }
}

private struct ExampleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("EXAMPLE BANK").font(.system(size: 40, weight: .heavy))
            Spacer()
            Text("4111 1111 1111 1111").font(.system(size: 54, weight: .semibold, design: .monospaced))
            HStack(spacing: 60) {
                Text("VALID FROM 01/26")
                Text("EXPIRES END 12/30")
            }
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            HStack {
                Text("JANE APPLESEED")
                Spacer()
                Text("00-00-00  00000000")
            }
            .font(.system(size: 30, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.22))
        .padding(48)
        .frame(width: 1080, height: 680, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.86, green: 0.92, blue: 0.97), Color(red: 0.70, green: 0.82, blue: 0.92)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 44))
    }
}

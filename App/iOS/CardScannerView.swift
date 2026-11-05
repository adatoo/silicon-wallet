import SiliconWalletKit
import SwiftUI
import VisionKit

/// Scans a card live with the camera, on this device (ADR-0009): the details found so far show
/// at the bottom, and Use hands them back. Frames are never saved.
struct LiveCardScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let side: CardScanSide
    /// The number already in the entry, so a back scan can skip its last four digits.
    let cardNumber: String?
    let onUse: (ScannedCard) -> Void
    @State private var found = ScannedCard()
    @State private var unavailable: String?

    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if let unavailable {
                    ContentUnavailableView("Camera Unavailable", systemImage: "camera", description: Text(unavailable))
                } else {
                    CardDataScanner(side: side, cardNumber: cardNumber, found: $found) { unavailable = $0 }
                        .ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            side == .front
                                ? "Hold the front of the card in view." : "Hold the back of the card in view."
                        )
                        .font(.headline)
                        ScannedCardSummary(card: found, side: side)
                    }
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding()
                }
            }
            .navigationTitle(side == .front ? "Scan Card" : "Scan Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(found)
                        dismiss()
                    }
                    .disabled(found.isEmpty)
                }
            }
        }
        .onAppear {
            if !DataScannerViewController.isAvailable {
                unavailable = "Allow Silicon Wallet to use the camera in Settings ▸ Privacy & Security ▸ Camera."
            }
        }
    }
}

/// VisionKit's live text scanner, reading every visible line on each update.
private struct CardDataScanner: UIViewControllerRepresentable {
    let side: CardScanSide
    let cardNumber: String?
    @Binding var found: ScannedCard
    let onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()], qualityLevel: .accurate, recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: CardDataScanner

        init(parent: CardDataScanner) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            read(allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            read(allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            parent.onUnavailable("The camera stopped. Close this and try again.")
        }

        private func read(_ items: [RecognizedItem]) {
            let lines = items.compactMap { item -> (CGPoint, String)? in
                guard case .text(let text) = item else { return nil }
                return (text.bounds.topLeft, text.transcript)
            }
            .sorted { abs($0.0.y - $1.0.y) > 12 ? $0.0.y < $1.0.y : $0.0.x < $1.0.x }
            .map(\.1)
            let card =
                parent.side == .front
                ? CardTextParser.front(lines) : CardTextParser.back(lines, cardNumber: parent.cardNumber)
            let merged = parent.found.merged(with: card)
            if merged != parent.found { parent.found = merged }
        }
    }
}

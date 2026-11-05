import CoreGraphics
import CoreImage
import SiliconWalletKit
import Vision

/// A card's four corners in an image, normalised with the origin at the top left.
struct CardQuad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var bounds: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

/// One line of text read from a card, with its box normalised to the image that was read (origin
/// top left), and the field it gave, if any.
struct RecognisedLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let box: CGRect
    var field: CardField?
}

/// What one look at a card found (ADR-0009). Held in memory only, for as long as a scan or its
/// review is on screen.
struct CardAnalysis: @unchecked Sendable {
    var card: ScannedCard
    /// Where the card is in the original image, if its edge was found.
    var quad: CardQuad?
    /// The lines read, in reading order, boxed in `image` (or in the original image when there's
    /// no corrected one).
    var lines: [RecognisedLine]
    /// The card straightened and cropped, for the review; nil for a live frame, or when no card
    /// edge was found and the review shows the photo as it came.
    var image: CGImage?
    /// The size of the original image, to place live boxes over the camera's preview.
    var imageSize: CGSize

    static let empty = CardAnalysis(card: ScannedCard(), quad: nil, lines: [], image: nil, imageSize: .zero)
}

/// Finds a card in an image and reads it, on this device, with Vision. Nothing is saved or
/// logged; the images exist only in memory.
enum CardImageAnalyzer {
    enum Detail {
        /// For live frames: read as they are, keeping only text on the card once it's found.
        case live
        /// For a captured photo: the card is straightened first, for the review.
        case still
    }

    /// An ID-1 card is 85.6 × 54 mm, 0.63 high for its width; allow for perspective.
    private static let aspect: ClosedRange<Float> = 0.5...0.75

    static func analyse(_ image: CGImage, side: CardScanSide, cardNumber: String?, detail: Detail) async throws
        -> CardAnalysis
    {
        let size = CGSize(width: image.width, height: image.height)
        let quad = try await findCard(in: image)
        var readImage = image
        var corrected: CGImage?
        if detail == .still, let quad, let straightened = straighten(image, quad: quad) {
            readImage = straightened
            corrected = straightened
        }
        // Accurate even live: fast recognition misreads embossed digits, and frames are dropped
        // while one is read, so the rate adapts to the device.
        var lines = try await readLines(in: readImage)
        // Live, ignore text outside the card once it's found: a table, a screen, a receipt.
        if detail == .live, let bounds = quad?.bounds.insetBy(dx: -0.02, dy: -0.02) {
            lines = lines.filter { bounds.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
        }
        let texts = lines.map(\.text)
        let card =
            side == .front ? CardTextParser.front(texts) : CardTextParser.back(texts, cardNumber: cardNumber)
        let sources = CardTextParser.sources(of: card, in: texts)
        let tagged = lines.enumerated().map { index, line in
            RecognisedLine(id: index, text: line.text, box: line.box, field: sources[index])
        }
        return CardAnalysis(card: card, quad: quad, lines: tagged, image: corrected, imageSize: size)
    }

    /// The most card-like rectangle, if there is one.
    static func findCard(in image: CGImage) async throws -> CardQuad? {
        var request = DetectRectanglesRequest()
        request.minimumAspectRatio = aspect.lowerBound
        request.maximumAspectRatio = aspect.upperBound
        request.minimumSize = 0.25
        request.minimumConfidence = 0.7
        request.quadratureToleranceDegrees = 25
        request.maximumObservations = 1
        guard let found = try await request.perform(on: image).first else { return nil }
        func flip(_ point: NormalizedPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }
        return CardQuad(
            topLeft: flip(found.topLeft), topRight: flip(found.topRight), bottomRight: flip(found.bottomRight),
            bottomLeft: flip(found.bottomLeft))
    }

    /// The card cut out and squared up, in memory.
    static func straighten(_ image: CGImage, quad: CardQuad) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // Core Image's origin is the bottom left.
        func vector(_ point: CGPoint) -> CIVector { CIVector(x: point.x * width, y: (1 - point.y) * height) }
        let input = CIImage(cgImage: image)
        guard
            let filter = CIFilter(
                name: "CIPerspectiveCorrection",
                parameters: [
                    kCIInputImageKey: input, "inputTopLeft": vector(quad.topLeft),
                    "inputTopRight": vector(quad.topRight),
                    "inputBottomRight": vector(quad.bottomRight), "inputBottomLeft": vector(quad.bottomLeft),
                ]),
            let output = filter.outputImage
        else { return nil }
        var straightened = output
        // A card held upright reads sideways; turn it so it's wider than tall.
        if output.extent.height > output.extent.width {
            straightened = output.oriented(.left)
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(straightened, from: straightened.extent)
    }

    /// Each line of text, top to bottom then left to right, with its box (origin top left).
    private static func readLines(in image: CGImage) async throws -> [(text: String, box: CGRect)] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Names and numbers aren't words; correction would "fix" them.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image)
        let lines = observations.compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            return (text, CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        return lines.sorted {
            abs($0.box.minY - $1.box.minY) > 0.02 ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX
        }
    }
}

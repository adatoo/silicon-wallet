import CoreGraphics
import SiliconWalletKit
import Testing

@testable import SiliconWallet

/// The inline graph centres all its entries, not just the one in the middle (#152).
struct RelatedGraphFitTests {
    /// A login with one account on one side and an account and its card on the other, as the
    /// layout gives them: after the wide turn, one entry to the left and two to the right.
    private let lopsided = [
        RelatedGraph.Point(x: 0, y: 0), RelatedGraph.Point(x: 0, y: -1),
        RelatedGraph.Point(x: 0, y: 1), RelatedGraph.Point(x: 0, y: -2),
    ]

    @Test func aLopsidedGraphIsCentredOnAllItsEntries() {
        let size = CGSize(width: 600, height: 120)
        let fit = CompactFit(points: lopsided, size: size)
        let xs = lopsided.map { fit.place($0).x }
        let left = xs.min() ?? 0
        let right = xs.max() ?? 0
        #expect(abs((left + right) / 2 - size.width / 2) < 0.5)
        #expect(left >= CompactFit.side - 0.5)
        #expect(right <= size.width - CompactFit.side + 0.5)
        // The entry on screen is no longer in the middle: the graph's extra ring pulls it left.
        #expect(fit.place(lopsided[0]).x < size.width / 2)
    }

    @Test func aWideRowDoesNotSpreadASmallGraph() {
        let fit = CompactFit(points: lopsided, size: CGSize(width: 1400, height: 120))
        let gap = fit.place(lopsided[3]).x - fit.place(lopsided[1]).x
        #expect(abs(gap - CompactFit.maxUnit) < 0.5)
    }

    @Test func theRowIsAsTallAsTheGraph() {
        #expect(CompactFit.height(for: lopsided) == CompactFit.heights.lowerBound)
        let square = [
            RelatedGraph.Point(x: 0, y: 0), RelatedGraph.Point(x: 1, y: 0), RelatedGraph.Point(x: -1, y: 0),
        ]
        #expect(CompactFit.height(for: square) == CompactFit.top + CompactFit.bottom + 2 * CompactFit.unitHeight)
        let tall = square + [RelatedGraph.Point(x: 2, y: 0), RelatedGraph.Point(x: -2, y: 0)]
        #expect(CompactFit.height(for: tall) == CompactFit.heights.upperBound)
    }

    @Test func nodesOnOneLineSitInTheMiddleOfTheCirclesRoom() {
        let size = CGSize(width: 600, height: 120)
        let fit = CompactFit(points: lopsided, size: size)
        let y = fit.place(lopsided[0]).y
        #expect(abs(y - (CompactFit.top + (size.height - CompactFit.top - CompactFit.bottom) / 2)) < 0.5)
    }
}

import Foundation

/// The entries around one entry, by related-entry links (DESIGN.md §4), for drawing as a graph.
/// Holds IDs only; the app looks the entries up to show their titles.
public struct RelatedGraph: Equatable, Sendable {
    public struct Node: Equatable, Identifiable, Sendable {
        public let id: UUID
        /// Links from the centre: 0 for the centre itself.
        public let depth: Int
        /// The node it was reached from; nil for the centre.
        public let parent: UUID?
    }

    /// A link between two nodes, whichever side stores it. `first` sorts before `second`.
    public struct Edge: Hashable, Identifiable, Sendable {
        public let first: UUID
        public let second: UUID

        public init(_ a: UUID, _ b: UUID) {
            (first, second) = a.uuidString < b.uuidString ? (a, b) : (b, a)
        }

        public var id: String { first.uuidString + second.uuidString }
    }

    /// A position in graph units: the centre is (0, 0) and each ring is one unit further out.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// No entry: the centre isn't in use.
    public static let empty = RelatedGraph(nodes: [], edges: [], isTruncated: false)

    /// The centre first, then outwards, in the order they were reached.
    public var nodes: [Node]
    public var edges: [Edge]
    /// The walk stopped at the node limit, so some related entries aren't shown.
    public var isTruncated: Bool

    public var centre: UUID? { nodes.first?.id }

    /// Whether `edge` is how the walk reached one of its ends; the others close a cycle.
    public func isTreeEdge(_ edge: Edge) -> Bool {
        nodes.contains {
            ($0.id == edge.first && $0.parent == edge.second) || ($0.id == edge.second && $0.parent == edge.first)
        }
    }

    /// A radial layout: the centre in the middle and each depth on its own ring. Every node gets
    /// a slice of its parent's angle, sized by how many outermost nodes lie beyond it, so
    /// branches don't overlap. The first ring starts at the top.
    public func layout() -> [UUID: Point] {
        guard let centre else { return [:] }
        var children: [UUID: [UUID]] = [:]
        for node in nodes {
            if let parent = node.parent { children[parent, default: []].append(node.id) }
        }
        var leaves: [UUID: Int] = [:]
        func countLeaves(_ id: UUID) -> Int {
            let count = max(1, (children[id] ?? []).reduce(0) { $0 + countLeaves($1) })
            leaves[id] = count
            return count
        }
        _ = countLeaves(centre)

        var points: [UUID: Point] = [centre: Point(x: 0, y: 0)]
        func place(_ id: UUID, depth: Int, from start: Double, to end: Double) {
            let kids = children[id] ?? []
            let total = Double(kids.reduce(0) { $0 + (leaves[$1] ?? 1) })
            var angle = start
            for kid in kids {
                let share = (end - start) * Double(leaves[kid] ?? 1) / total
                let middle = angle + share / 2
                let radius = Double(depth + 1)
                points[kid] = Point(x: radius * cos(middle), y: radius * sin(middle))
                place(kid, depth: depth + 1, from: angle, to: angle + share)
                angle += share
            }
        }
        // Starts so that the first entry on the first ring is straight up (y grows downwards).
        let first = children[centre]?.first.flatMap { leaves[$0] } ?? 1
        let start = -Double.pi / 2 - .pi * Double(first) / Double(leaves[centre] ?? 1)
        place(centre, depth: 0, from: start, to: start + 2 * .pi)
        return points
    }
}

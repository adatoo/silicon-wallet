import SiliconWalletKit
import SwiftUI

/// Related entries as a graph (DESIGN.md §3): the entry in the middle, its related entries on
/// the first ring and theirs on the second. Choosing an entry moves it to the middle; choosing
/// the one in the middle, or Open, opens it. Shows titles and group icons, never a value.
struct RelatedGraphSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var centreID: UUID
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    init(entryID: UUID) {
        _centreID = State(initialValue: entryID)
    }

    private static let zoomRange: ClosedRange<CGFloat> = 0.5...3

    var body: some View {
        let graph =
            model.session?.relatedGraph(from: centreID) ?? .empty
        NavigationStack {
            Group {
                if let centre = graph.centre, let entry = model.session?.entry(id: centre) {
                    canvas(graph)
                        .navigationTitle(entry.title.isEmpty ? "Untitled" : entry.title)
                } else {
                    ContentUnavailableView("Entry Deleted", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { setZoom(zoom / 1.25) }
                        .keyboardShortcut("-")
                        .disabled(zoom <= Self.zoomRange.lowerBound)
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { setZoom(zoom * 1.25) }
                        .keyboardShortcut("+")
                        .disabled(zoom >= Self.zoomRange.upperBound)
                    Button("Open", systemImage: "arrow.forward.circle") { open(centreID) }
                        .disabled(graph.centre == nil)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 580)
        #endif
    }

    private func canvas(_ graph: RelatedGraph) -> some View {
        RelatedGraphCanvas(graph: graph, isCompact: false, zoom: zoom, offset: offset) { node in
            if node.depth == 0 {
                open(node.id)
            } else {
                recentre(on: node.id)
            }
        } onOpen: { id in
            open(id)
        }
        .contentShape(.rect)
        .gesture(drag)
        .simultaneousGesture(magnify)
        .overlay(alignment: .bottom) {
            if graph.isTruncated {
                Text("Showing the nearest \(graph.nodes.count) entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                offset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = (settledZoom * value.magnification).clamped(to: Self.zoomRange) }
            .onEnded { _ in settledZoom = zoom }
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.snappy) { zoom = value.clamped(to: Self.zoomRange) }
        settledZoom = zoom
    }

    private func recentre(on id: UUID) {
        withAnimation(.snappy) {
            centreID = id
            offset = .zero
        }
        settledOffset = .zero
    }

    private func open(_ id: UUID) {
        dismiss()
        model.reveal(id)
    }
}

/// Draws a related graph: lines, then the nodes on top. The sheet's full size pans and zooms;
/// the compact one sits inline in the entry view (DESIGN.md §3), fitted to a short, wide row.
struct RelatedGraphCanvas: View {
    @Environment(AppModel.self) private var model
    let graph: RelatedGraph
    let isCompact: Bool
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    let onTap: (RelatedGraph.Node) -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        let points = graph.layout()
        let rings = graph.nodes.map(\.depth).max() ?? 0
        let depths = Dictionary(graph.nodes.map { ($0.id, $0.depth) }) { first, _ in first }
        GeometryReader { proxy in
            let fit = isCompact ? CompactFit(points: points.values, size: proxy.size) : nil
            let frame = Frame(size: proxy.size, rings: rings, zoom: zoom, offset: offset, fit: fit)
            ZStack {
                ForEach(graph.edges) { edge in
                    let isTree = graph.isTreeEdge(edge)
                    EdgeLine(
                        from: frame.place(points[edge.first]), to: frame.place(points[edge.second]),
                        fromInset: radius(isCentre: depths[edge.first] == 0),
                        toInset: radius(isCentre: depths[edge.second] == 0)
                    )
                    .stroke(
                        Color.secondary.opacity(isTree ? 0.6 : 0.35),
                        style: StrokeStyle(lineWidth: isCompact ? 1.2 : 1.5, dash: isTree ? [] : [4, 4])
                    )
                    .accessibilityHidden(true)
                }
                ForEach(graph.nodes) { node in
                    if let entry = model.session?.entry(id: node.id) {
                        GraphNode(entry: entry, isCentre: node.depth == 0, isCompact: isCompact) {
                            onTap(node)
                        } open: {
                            onOpen(node.id)
                        }
                        .position(frame.place(points[node.id]))
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityElement(children: .contain)
        }
    }

    private func radius(isCentre: Bool) -> CGFloat {
        GraphNode.diameter(isCentre: isCentre, isCompact: isCompact) / 2
    }
}

/// Maps the layout's graph units to points in the view.
private struct Frame {
    let size: CGSize
    let rings: Int
    let zoom: CGFloat
    let offset: CGSize
    let fit: CompactFit?

    func place(_ point: RelatedGraph.Point?) -> CGPoint {
        if let fit { return fit.place(point) }
        // The full graph keeps its rings round, sized to the shorter side.
        let rings = CGFloat(max(rings, 1))
        let unit: CGFloat = max(70, (min(size.width, size.height) / 2 - 64) / rings) * zoom
        // The layout puts the first ring's first entry at the top; in a wide view it goes to the
        // right instead, so the graph spreads along the longer side.
        let isWide = size.width > size.height
        let drawn = point.map { isWide ? CompactFit.drawn($0) : CGPoint(x: $0.x, y: $0.y) } ?? .zero
        return CGPoint(
            x: size.width / 2 + offset.width + drawn.x * unit,
            y: size.height / 2 + offset.height + drawn.y * unit)
    }
}

/// Fits the inline graph to its entries (DESIGN.md §3): the box round them, titles included,
/// is stretched to the row, no more than `maxUnit` per ring so a small graph stays together,
/// and centred in it. The graph always spreads along the row.
struct CompactFit {
    /// The most points per ring unit, across or down.
    static let maxUnit: CGFloat = 150
    /// The height each ring unit gets when the row is sized to the graph.
    static let unitHeight: CGFloat = 70
    /// Room round the circles for what hangs off them: half a title across, the circle's radius
    /// above, and the radius plus a two-line title below.
    static let side: CGFloat = 60
    static let top: CGFloat = 24
    static let bottom: CGFloat = 58
    static let heights: ClosedRange<CGFloat> = 110...300

    let size: CGSize
    private let box: CGRect

    init(points: some Collection<RelatedGraph.Point>, size: CGSize) {
        self.size = size
        box = Self.box(points)
    }

    func place(_ point: RelatedGraph.Point?) -> CGPoint {
        let drawn = point.map(Self.drawn) ?? .zero
        let width = max(0, size.width - 2 * Self.side)
        let height = max(0, size.height - Self.top - Self.bottom)
        let unitX = box.width > 0 ? min(width / box.width, Self.maxUnit) : 0
        let unitY = box.height > 0 ? min(height / box.height, Self.maxUnit) : 0
        return CGPoint(
            x: size.width / 2 + (drawn.x - box.midX) * unitX,
            y: Self.top + height / 2 + (drawn.y - box.midY) * unitY)
    }

    /// The row height for these points: a graph on one line gets the shortest row.
    static func height(for points: some Collection<RelatedGraph.Point>) -> CGFloat {
        (top + bottom + box(points).height * unitHeight).clamped(to: heights)
    }

    /// A layout point as drawn in a wide view: the first ring's first entry to the right.
    static func drawn(_ point: RelatedGraph.Point) -> CGPoint {
        CGPoint(x: -point.y, y: point.x)
    }

    private static func box(_ points: some Collection<RelatedGraph.Point>) -> CGRect {
        let xs = points.map { Self.drawn($0).x }
        let ys = points.map { Self.drawn($0).y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A straight line between two nodes, stopping at their circles, whose ends animate with them.
private struct EdgeLine: Shape {
    var from: CGPoint
    var to: CGPoint
    let fromInset: CGFloat
    let toInset: CGFloat

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(from.animatableData, to.animatableData) }
        set {
            from.animatableData = newValue.first
            to.animatableData = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > fromInset + toInset else { return Path() }
        let ux = dx / length
        let uy = dy / length
        return Path { path in
            path.move(to: CGPoint(x: from.x + ux * fromInset, y: from.y + uy * fromInset))
            path.addLine(to: CGPoint(x: to.x - ux * toInset, y: to.y - uy * toInset))
        }
    }
}

/// One entry in the graph: its group's icon in a circle, with the title underneath.
private struct GraphNode: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    let isCentre: Bool
    let isCompact: Bool
    let action: () -> Void
    let open: () -> Void

    static func diameter(isCentre: Bool, isCompact: Bool) -> CGFloat {
        switch (isCompact, isCentre) {
        case (false, true): 56
        case (false, false): 44
        case (true, true): 44
        case (true, false): 34
        }
    }

    var body: some View {
        let group = model.session?.group(id: entry.groupID)
        let title = entry.title.isEmpty ? "Untitled" : entry.title
        let diameter = Self.diameter(isCentre: isCentre, isCompact: isCompact)
        Button(action: action) {
            // Only the circle takes up space, so the node's position is the circle's centre and
            // the lines meet it there; the title hangs underneath.
            GroupSymbol(group?.icon)
                .font(isCompact ? (isCentre ? .title3 : .body) : (isCentre ? .title2 : .title3))
                .foregroundStyle(isCentre ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .frame(width: diameter, height: diameter)
                .background(isCentre ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: .circle)
                .overlay(alignment: .top) {
                    // Inline, the middle is the entry on screen, already titled above.
                    if !(isCompact && isCentre) {
                        nodeTitle(title, diameter: diameter)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!(isCompact && isCentre))
        .help(helpText(title))
        .accessibilityLabel("\(title), \(group?.name ?? "No group")")
        .accessibilityHint(isCentre ? "Opens this entry." : "Moves this entry to the middle of the graph.")
        .contextMenu {
            if !(isCompact && isCentre) {
                Button("Open", systemImage: "arrow.forward.circle", action: open)
            }
        }
    }

    private func nodeTitle(_ title: String, diameter: CGFloat) -> some View {
        Text(title)
            .font(isCentre ? .caption.weight(.semibold) : .caption)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            // A line can pass under a title; keep it readable.
            .background(.background.opacity(0.9), in: .rect(cornerRadius: 4))
            .frame(width: 120)
            .fixedSize(horizontal: false, vertical: true)
            // Below the circle; an offset doesn't change the node's size or centre.
            .offset(y: diameter + 3)
    }

    private func helpText(_ title: String) -> String {
        if isCompact { return "Open \(title)" }
        return isCentre ? "Open \(title)" : "Show what's related to \(title)"
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

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
        let points = graph.layout()
        let rings = graph.nodes.map(\.depth).max() ?? 0
        return GeometryReader { proxy in
            let frame = Frame(size: proxy.size, rings: rings, zoom: zoom, offset: offset)
            ZStack {
                ForEach(graph.edges) { edge in
                    let isTree = graph.isTreeEdge(edge)
                    EdgeLine(from: frame.place(points[edge.first]), to: frame.place(points[edge.second]))
                        .stroke(
                            Color.secondary.opacity(isTree ? 0.6 : 0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: isTree ? [] : [4, 4])
                        )
                        .accessibilityHidden(true)
                }
                ForEach(graph.nodes) { node in
                    if let entry = model.session?.entry(id: node.id) {
                        GraphNode(entry: entry, isCentre: node.depth == 0) {
                            if node.depth == 0 {
                                open(node.id)
                            } else {
                                recentre(on: node.id)
                            }
                        } open: {
                            open(node.id)
                        }
                        .position(frame.place(points[node.id]))
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(drag)
            .simultaneousGesture(magnify)
            .accessibilityElement(children: .contain)
            .overlay(alignment: .bottom) {
                if graph.isTruncated {
                    Text("Showing the nearest \(graph.nodes.count) entries.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
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

/// Maps the layout's graph units to points in the view.
private struct Frame {
    let size: CGSize
    let rings: Int
    let zoom: CGFloat
    let offset: CGSize

    /// Room at the edge for a node's icon and title.
    private static let margin: CGFloat = 64

    func place(_ point: RelatedGraph.Point?) -> CGPoint {
        let radius: CGFloat = min(size.width, size.height) / 2 - Self.margin
        let unit: CGFloat = max(70, radius / CGFloat(max(rings, 1))) * zoom
        // The layout puts the first ring's first entry at the top; in a wide view it goes to the
        // right instead, so the graph spreads along the longer side.
        let isWide = size.width > size.height
        let gx: CGFloat = CGFloat(isWide ? -(point?.y ?? 0) : (point?.x ?? 0))
        let gy: CGFloat = CGFloat(isWide ? (point?.x ?? 0) : (point?.y ?? 0))
        let x: CGFloat = size.width / 2 + offset.width + gx * unit
        let y: CGFloat = size.height / 2 + offset.height + gy * unit
        return CGPoint(x: x, y: y)
    }
}

/// A straight line whose ends animate with the nodes they join.
private struct EdgeLine: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(from.animatableData, to.animatableData) }
        set {
            from.animatableData = newValue.first
            to.animatableData = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
    }
}

/// One entry in the graph: its group's icon in a circle, with the title underneath.
private struct GraphNode: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    let isCentre: Bool
    let action: () -> Void
    let open: () -> Void

    var body: some View {
        let group = model.session?.group(id: entry.groupID)
        let title = entry.title.isEmpty ? "Untitled" : entry.title
        let diameter: CGFloat = isCentre ? 56 : 44
        Button(action: action) {
            // Only the circle takes up space, so the node's position is the circle's centre and
            // the lines meet it there; the title hangs underneath.
            GroupSymbol(group?.icon)
                .font(isCentre ? .title2 : .title3)
                .foregroundStyle(isCentre ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .frame(width: diameter, height: diameter)
                // Opaque underneath, so the lines stop at the circle rather than show through.
                .background(isCentre ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: .circle)
                .background(.background, in: .circle)
                .overlay(alignment: .top) {
                    Text(title)
                        .font(isCentre ? .caption.weight(.semibold) : .caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .background(.background.opacity(0.9), in: .rect(cornerRadius: 4))
                        .frame(width: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.top) { _ in -(diameter + 4) }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(isCentre ? "Open \(title)" : "Show what's related to \(title)")
        .accessibilityLabel("\(title), \(group?.name ?? "No group")")
        .accessibilityHint(isCentre ? "Opens this entry." : "Moves this entry to the middle of the graph.")
        .contextMenu {
            Button("Open", systemImage: "arrow.forward.circle", action: open)
        }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

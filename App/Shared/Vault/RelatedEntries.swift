import SiliconWalletKit
import SwiftUI

/// A related entry as a row: its group's icon, title and group, never a value (DESIGN.md §3).
struct RelatedEntryLabel: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry

    var body: some View {
        let group = model.session?.group(id: entry.groupID)
        HStack(spacing: 10) {
            GroupSymbol(group?.icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                Text(group?.name ?? "No group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The entry view's Related section: each row opens that entry.
struct RelatedEntriesSection: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    @State private var showingGraph = false

    var body: some View {
        let related = entry.deleted == nil ? (model.session?.relatedEntries(of: entry.id) ?? []) : []
        if !related.isEmpty {
            Section {
                InlineRelatedGraph(entryID: entry.id)
                ForEach(related) { other in
                    Button {
                        model.reveal(other.id)
                    } label: {
                        HStack {
                            RelatedEntryLabel(entry: other)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(other.title)")
                    .accessibilityLabel("Open \(other.title)")
                }
            } header: {
                HStack {
                    Text("Related")
                    Spacer()
                    Button("Expand Graph", systemImage: "arrow.up.left.and.arrow.down.right") { showingGraph = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open the graph full size, to zoom and move around")
                        .sheet(isPresented: $showingGraph) { RelatedGraphSheet(entryID: entry.id) }
                }
            }
        }
    }
}

/// The compact graph at the top of the Related section: up to two links away and twelve
/// entries, no zooming. Choosing an entry opens it, with its own graph. VoiceOver skips it,
/// since the rows below list the same entries.
private struct InlineRelatedGraph: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID

    @State private var width: CGFloat = 0

    private static let limit = 12

    var body: some View {
        // Two rings need the width of a Mac or iPad detail column; a phone shows one.
        let depth = width >= 420 ? 2 : 1
        let graph = model.session?.relatedGraph(from: entryID, depth: depth, limit: Self.limit) ?? .empty
        VStack(spacing: 4) {
            RelatedGraphCanvas(graph: graph, isCompact: true) { node in
                if node.depth > 0 { model.reveal(node.id) }
            } onOpen: { id in
                model.reveal(id)
            }
            .frame(height: CompactFit.height(for: graph.layout().values))
            if graph.isTruncated {
                Text("Showing the nearest \(Self.limit); expand to see all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .accessibilityHidden(true)
    }
}

/// Chooses an entry to relate to the one being edited: any entry in use except `excluded`.
struct RelatedEntryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let excluded: Set<UUID>
    let onPick: (VaultEntry) -> Void
    @State private var query = ""

    var body: some View {
        let choices = (model.session?.search(query) ?? []).filter { !excluded.contains($0.id) }
        NavigationStack {
            Group {
                if choices.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No Other Entries" : "No Results", systemImage: "link",
                        description: Text(query.isEmpty ? "Every entry is already related." : "Try another search."))
                } else {
                    List(choices) { entry in
                        Button {
                            onPick(entry)
                            dismiss()
                        } label: {
                            RelatedEntryLabel(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search entries")
            .navigationTitle("Add Related Entry")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 420, idealWidth: 480, minHeight: 420, idealHeight: 520)
        #endif
    }
}

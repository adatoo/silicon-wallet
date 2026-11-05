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
                    Button("Show Graph", systemImage: "point.3.connected.trianglepath.dotted") { showingGraph = true }
                        .buttonStyle(.borderless)
                        .help("Show related entries as a graph")
                        .sheet(isPresented: $showingGraph) { RelatedGraphSheet(entryID: entry.id) }
                }
            }
        }
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

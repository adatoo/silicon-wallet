import SiliconWalletKit
import SwiftUI

/// One entry in the card view: its group's icon, title, first visible value and group. Concealed
/// values never appear on a card.
struct EntryCard: View {
    let entry: VaultEntry
    let group: VaultGroup?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: group?.icon ?? "questionmark.folder")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 9))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favourite")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                    .lineLimit(1)
                let value = entry.firstVisibleValue(in: group)
                Text(value?.text ?? " ")
                    .font(.subheadline)
                    .fontDesign(value?.isMonospaced == true ? .monospaced : nil)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(group?.name ?? "No group")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovered ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.fill.quinary), in: .rect(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .contentShape(.rect(cornerRadius: 14))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// An entry opened from the card view: the same detail as the list's third column, in a sheet.
/// It follows edits and sync changes, and closes if the entry is deleted. From Recently Deleted
/// it shows the deleted entry, read-only.
struct EntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entryID: VaultEntry.ID
    @State private var editor: EditorTarget?

    var body: some View {
        let entry = model.entryToShow(id: entryID)
        NavigationStack {
            Group {
                if let entry {
                    EntryDetailView(entry: entry, editor: $editor)
                } else {
                    ContentUnavailableView("Entry Deleted", systemImage: "key.horizontal")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 640)
        #endif
        .sheet(item: $editor) { EditorSheet(target: $0) }
        .onChange(of: entry == nil) { _, deleted in
            if deleted { dismiss() }
        }
    }
}

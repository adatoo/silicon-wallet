import SiliconWalletKit
import SwiftUI

/// The third column: one entry's fields, notes and attachments.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    @Binding var editor: EditorTarget?
    @State private var attachmentPresentation = AttachmentPresentation()

    private var group: VaultGroup? { model.session?.group(id: entry.groupID) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: group?.icon ?? "questionmark.folder")
                        .font(.title)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.isEmpty ? "Untitled" : entry.title)
                            .font(.title2.bold())
                            .textSelection(.enabled)
                        Text(group?.name ?? "No group")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            let rows = fieldRows
            if !rows.isEmpty {
                Section("Details") {
                    ForEach(rows) { row in
                        FieldValueRow(row: row)
                    }
                }
            }

            if !entry.notes.isEmpty {
                Section("Notes") {
                    Text(entry.notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AttachmentsSection(entry: entry, presentation: $attachmentPresentation)

            Section {
                LabeledContent("Created", value: entry.created.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: entry.modified.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .attachmentPresentations(for: entry, $attachmentPresentation)
        .navigationTitle(entry.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button(
                    entry.isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: entry.isFavorite ? "star.fill" : "star"
                ) {
                    model.perform { try model.session?.setFavorite(!entry.isFavorite, entryID: entry.id) }
                }
                Button("Edit", systemImage: "pencil") { editor = .entry(entry) }
                    .keyboardShortcut("e")
            }
        }
    }

    private var fieldRows: [FieldValueRow.Row] {
        var rows: [FieldValueRow.Row] = []
        for field in group?.fields ?? [] {
            guard let value = entry.values[field.id], !value.isEmpty else { continue }
            rows.append(
                .init(
                    id: field.id, label: field.label, kind: field.kind, isConcealed: field.isConcealed,
                    isMonospaced: field.isMonospaced, value: value))
        }
        for field in entry.extraFields where !field.value.isEmpty {
            rows.append(
                .init(
                    id: field.id, label: field.label, kind: field.kind, isConcealed: field.isConcealed,
                    isMonospaced: field.isMonospaced, value: field.value))
        }
        return rows
    }
}

/// One labelled value, concealed until revealed, with copy and open actions.
struct FieldValueRow: View {
    struct Row: Identifiable {
        let id: UUID
        let label: String
        let kind: FieldKind
        let isConcealed: Bool
        let isMonospaced: Bool
        let value: String
    }

    let row: Row
    @State private var isRevealed = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.label.isEmpty ? row.kind.displayName : row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                valueText
            }
            Spacer(minLength: 8)
            if row.isConcealed {
                Button(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye") {
                    isRevealed.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide" : "Reveal")
            }
            if let link = row.kind.link(for: row.value) {
                Link(destination: link) { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .help("Open")
                    .accessibilityLabel("Open \(row.label)")
            }
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(row.value, concealed: row.isConcealed)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Copy \(row.label)")
            .accessibilityLabel("Copy \(row.label)")
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(row.value, concealed: row.isConcealed) }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if row.isConcealed && !isRevealed {
            Text(String(repeating: "•", count: 10))
                .font(.body.monospaced())
                .accessibilityLabel("Concealed")
        } else {
            Text(row.value)
                .font(row.isMonospaced ? .body.monospaced() : .body)
                .textSelection(.enabled)
        }
    }
}

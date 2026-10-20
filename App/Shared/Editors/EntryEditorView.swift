import SiliconWalletKit
import SwiftUI

/// Adds or edits an entry. Changes are saved only when you press Save, which asks first if it
/// would delete attachments or filled-in extra fields for good.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VaultEntry
    /// What Save would delete, while the confirmation is showing.
    @State private var pendingRemovals: EntryRemovals?
    private let isNew: Bool
    /// The entry as it was opened; nil for a new one.
    private let original: VaultEntry?

    init(entry: VaultEntry?, preferredGroupID: UUID?) {
        isNew = entry == nil
        original = entry
        _draft = State(initialValue: entry ?? VaultEntry(groupID: preferredGroupID ?? UUID(), title: ""))
    }

    private var groups: [VaultGroup] { model.session?.groups ?? [] }
    private var group: VaultGroup? { model.session?.group(id: draft.groupID) }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                Picker("Group", selection: groupBinding) {
                    ForEach(groups) { group in
                        Label(group.name, systemImage: group.icon).tag(group.id)
                    }
                }
            }

            if let group, !group.fields.isEmpty {
                Section(group.name) {
                    ForEach(group.fields) { field in
                        FieldInput(
                            label: field.label, kind: field.kind, isConcealed: field.isConcealed,
                            isMonospaced: field.isMonospaced, value: valueBinding(field.id))
                    }
                }
            }

            Section {
                ForEach($draft.extraFields) { $field in
                    ExtraFieldInput(field: $field) {
                        draft.extraFields.removeAll { $0.id == field.id }
                    }
                    .reorderable(field, in: $draft.extraFields, title: field.label)
                }
                #if os(iOS)
                    .onMove { draft.extraFields.move(fromOffsets: $0, toOffset: $1) }
                #endif
                Button("Add Field", systemImage: "plus") {
                    draft.extraFields.append(CustomField(label: ""))
                }
            } header: {
                Text("Extra Fields")
            } footer: {
                Text("Fields for this entry only. To give every entry in the group a field, edit the group.")
            }

            if !draft.attachments.isEmpty {
                Section {
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            AttachmentRow(
                                attachment: attachment,
                                isAvailable: model.session?.isAttachmentAvailable(attachment) ?? false)
                            Spacer()
                            Button("Remove Attachment", systemImage: "minus.circle.fill", role: .destructive) {
                                draft.attachments.removeAll { $0.id == attachment.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove \(attachment.filename) when you save")
                        }
                        .reorderable(attachment, in: $draft.attachments, title: attachment.filename)
                    }
                    #if os(iOS)
                        .onMove { draft.attachments.move(fromOffsets: $0, toOffset: $1) }
                    #endif
                } header: {
                    Text("Attachments")
                } footer: {
                    Text(
                        "Drag to change the order. A removed attachment is deleted when you save. Add and open attachments from the entry itself."
                    )
                }
            }

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(4...)
                    .returnAddsLine()
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New Entry" : "Edit Entry")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Shows the drag handles for reordering extra fields and attachments.
            .environment(\.editMode, .constant(.active))
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: requestSave)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || group == nil)
            }
        }
        .onAppear {
            if group == nil, let first = groups.first { draft.groupID = first.id }
        }
        .confirmationDialog(
            pendingRemovals.map(Self.confirmationTitle) ?? "",
            isPresented: Binding(get: { pendingRemovals != nil }, set: { if !$0 { pendingRemovals = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemovals
        ) { _ in
            Button("Delete and Save", role: .destructive, action: save)
            Button("Cancel", role: .cancel) {}
        } message: { removals in
            Text(Self.confirmationMessage(removals))
        }
    }

    /// Saves, unless that would delete attachments or filled-in extra fields: then it asks first.
    private func requestSave() {
        let removals = original.map { draft.removals(since: $0) }
        if let removals, !removals.isEmpty {
            pendingRemovals = removals
        } else {
            save()
        }
    }

    /// "Delete 2 attachments and 1 field?"
    private static func confirmationTitle(_ removals: EntryRemovals) -> String {
        let parts = [
            count(removals.attachments.count, "attachment", "attachments"),
            count(removals.extraFields.count, "field", "fields"),
        ].compactMap(\.self)
        return "Delete \(parts.joined(separator: " and "))?"
    }

    /// Names what goes, by filename or label (never a field's value, which may be concealed).
    private static func confirmationMessage(_ removals: EntryRemovals) -> String {
        var names =
            removals.attachments.map { "\u{201C}\($0.filename)\u{201D}" }
            + removals.extraFields.map { $0.label.isEmpty ? "an unnamed field" : "\u{201C}\($0.label)\u{201D}" }
        let shown = 4
        if names.count > shown + 1 {
            let more = names.count - shown
            names = Array(names.prefix(shown)) + ["\(more) more"]
        }
        let list = names.formatted(.list(type: .and))
        return
            "\(list.prefix(1).uppercased() + list.dropFirst()) will be deleted from this vault on all your devices. This can't be undone."
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String? {
        switch n {
        case 0: nil
        case 1: "1 \(one)"
        default: "\(n) \(many)"
        }
    }

    /// Changing the group carries every value across (`VaultEntry.moved(from:to:)`).
    private var groupBinding: Binding<UUID> {
        Binding(
            get: { draft.groupID },
            set: { newID in
                guard let old = group, let new = model.session?.group(id: newID) else {
                    draft.groupID = newID
                    return
                }
                draft = draft.moved(from: old, to: new)
            })
    }

    private func valueBinding(_ fieldID: UUID) -> Binding<String> {
        Binding(
            get: { draft.values[fieldID] ?? "" },
            set: { draft.values[fieldID] = $0.isEmpty ? nil : $0 })
    }

    private func save() {
        guard let session = model.session else { return }
        var entry = draft
        entry.title = entry.title.trimmingCharacters(in: .whitespaces)
        entry.extraFields.removeAll { $0.label.isEmpty && $0.value.isEmpty }
        do {
            if isNew {
                let saved = try session.addEntry(entry)
                model.entrySelection = saved.id
            } else {
                try session.updateEntry(entry)
            }
            dismiss()
        } catch {
            model.errorMessage = AppModel.describe(error)
        }
    }
}

/// A labelled input for one value, concealed by default for secret fields. Long labels and values
/// wrap instead of being cut off or scrolling, so all of them show while editing. Long text goes
/// under its label at full width.
struct FieldInput: View {
    let label: String
    let kind: FieldKind
    let isConcealed: Bool
    let isMonospaced: Bool
    @Binding var value: String
    @State private var isRevealed = false
    @State private var generating = false

    var body: some View {
        Group {
            if kind == .multiline {
                VStack(alignment: .leading, spacing: 6) {
                    labelText
                    TextField(label, text: $value, axis: .vertical)
                        .lineLimit(3...)
                        .fieldStyle(kind, isMonospaced: isMonospaced)
                        .returnAddsLine()
                }
            } else {
                LabeledContent {
                    HStack {
                        Group {
                            if isConcealed && !isRevealed {
                                SecureField(label, text: $value)
                            } else {
                                TextField(label, text: $value, axis: .vertical)
                                    .lineLimit(1...)
                            }
                        }
                        .fieldStyle(kind, isMonospaced: isMonospaced)
                        if isConcealed {
                            Button(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye") {
                                isRevealed.toggle()
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        if kind == .password {
                            Button("Generate Password", systemImage: "wand.and.stars") { generating = true }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Generate a password")
                        }
                    }
                } label: {
                    labelText
                }
            }
        }
        .onChange(of: value) { old, new in
            // Outside Long Text, a line break typed into a value becomes a space. Line breaks
            // already in a value are left alone.
            if kind != .multiline, !old.contains(where: \.isNewline), new.contains(where: \.isNewline) {
                value = new.split(whereSeparator: \.isNewline).joined(separator: " ")
            }
        }
        .sheet(isPresented: $generating) {
            NavigationStack {
                GeneratorView { value = $0 }
            }
        }
    }

    private var labelText: some View {
        Text(label.isEmpty ? kind.displayName : label)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// The font, keyboard and text behaviour of a value's input.
    fileprivate func fieldStyle(_ kind: FieldKind, isMonospaced: Bool) -> some View {
        fontDesign(isMonospaced ? .monospaced : .default)
            .labelsHidden()
            .fieldInput(kind)
            .textContentType(nil)
    }
}

/// An entry-only field: its label, kind and value.
struct ExtraFieldInput: View {
    @Binding var field: CustomField
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabelField(label: $field.label)
                    .font(.callout.weight(.medium))
                Menu {
                    Picker("Kind", selection: $field.kind) {
                        ForEach(FieldKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Toggle("Concealed", isOn: $field.isConcealed)
                    Toggle("Monospaced", isOn: $field.isMonospaced)
                } label: {
                    Image(systemName: field.kind.symbol)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Field kind")
                Button("Remove Field", systemImage: "minus.circle.fill", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            FieldInput(
                label: "Value", kind: field.kind, isConcealed: field.isConcealed, isMonospaced: field.isMonospaced,
                value: $field.value)
        }
        .onChange(of: field.kind) { old, new in
            if old.isConcealedByDefault != new.isConcealedByDefault {
                field.isConcealed = new.isConcealedByDefault
                field.isMonospaced = new.isMonospacedByDefault(isConcealed: field.isConcealed)
            }
        }
    }
}

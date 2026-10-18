import SiliconWalletKit
import SwiftUI

/// Adds or edits an entry. Changes are saved only when you press Save.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VaultEntry
    private let isNew: Bool

    init(entry: VaultEntry?, preferredGroupID: UUID?) {
        isNew = entry == nil
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
                            value: valueBinding(field.id))
                    }
                }
            }

            Section {
                ForEach($draft.extraFields) { $field in
                    ExtraFieldInput(field: $field) {
                        draft.extraFields.removeAll { $0.id == field.id }
                    }
                }
                Button("Add Field", systemImage: "plus") {
                    draft.extraFields.append(CustomField(label: ""))
                }
            } header: {
                Text("Extra Fields")
            } footer: {
                Text("Fields for this entry only. To give every entry in the group a field, edit the group.")
            }

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(4...12)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New Entry" : "Edit Entry")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || group == nil)
            }
        }
        .onAppear {
            if group == nil, let first = groups.first { draft.groupID = first.id }
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

/// A labelled input for one value, concealed by default for secret fields.
struct FieldInput: View {
    let label: String
    let kind: FieldKind
    let isConcealed: Bool
    @Binding var value: String
    @State private var isRevealed = false
    @State private var generating = false

    var body: some View {
        LabeledContent(label.isEmpty ? kind.displayName : label) {
            HStack {
                Group {
                    if kind == .multiline {
                        TextField(label, text: $value, axis: .vertical)
                            .lineLimit(2...8)
                    } else if isConcealed && !isRevealed {
                        SecureField(label, text: $value)
                    } else {
                        TextField(label, text: $value)
                            .fontDesign(isConcealed ? .monospaced : .default)
                    }
                }
                .labelsHidden()
                .fieldInput(kind)
                .textContentType(nil)
                if isConcealed && kind != .multiline {
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
        }
        .sheet(isPresented: $generating) {
            NavigationStack {
                GeneratorView { value = $0 }
            }
        }
    }
}

/// An entry-only field: its label, kind and value.
struct ExtraFieldInput: View {
    @Binding var field: CustomField
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Label", text: $field.label)
                    .font(.callout.weight(.medium))
                Menu {
                    Picker("Kind", selection: $field.kind) {
                        ForEach(FieldKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Toggle("Concealed", isOn: $field.isConcealed)
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
            FieldInput(label: "Value", kind: field.kind, isConcealed: field.isConcealed, value: $field.value)
        }
        .onChange(of: field.kind) { old, new in
            if old.isConcealedByDefault != new.isConcealedByDefault { field.isConcealed = new.isConcealedByDefault }
        }
    }
}

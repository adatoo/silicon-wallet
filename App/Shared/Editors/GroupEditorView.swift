import SiliconWalletKit
import SwiftUI

/// Adds or edits a group: its name, icon and the field template its entries share.
struct GroupEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VaultGroup
    private let isNew: Bool

    init(group: VaultGroup?) {
        isNew = group == nil
        _draft = State(
            initialValue: group
                ?? VaultGroup(
                    name: "", icon: "folder",
                    fields: [FieldTemplate(label: "Username"), FieldTemplate(label: "Password", kind: .password)]))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                LabeledContent("Icon") {
                    IconGrid(selection: $draft.icon)
                }
            }

            Section {
                ForEach($draft.fields) { $field in
                    TemplateFieldRow(field: $field)
                }
                .onDelete { draft.fields.remove(atOffsets: $0) }
                .onMove { draft.fields.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Field", systemImage: "plus") {
                    draft.fields.append(FieldTemplate(label: ""))
                }
            } header: {
                Text("Fields")
            } footer: {
                Text(
                    "Every entry in this group gets these fields. Removing a field hides its values in existing entries."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New Group" : "Edit Group")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        guard let session = model.session else { return }
        var group = draft
        group.name = group.name.trimmingCharacters(in: .whitespaces)
        group.fields.removeAll { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            if isNew {
                let saved = try session.addGroup(group)
                model.sidebarSelection = .group(saved.id)
            } else {
                try session.updateGroup(group)
            }
            dismiss()
        } catch {
            model.errorMessage = AppModel.describe(error)
        }
    }
}

/// One field of a group's template.
struct TemplateFieldRow: View {
    @Binding var field: FieldTemplate

    var body: some View {
        HStack {
            TextField("Label", text: $field.label)
            Picker("Kind", selection: $field.kind) {
                ForEach(FieldKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
            .fixedSize()
            Toggle(isOn: $field.isConcealed) {
                Image(systemName: field.isConcealed ? "eye.slash" : "eye")
            }
            .toggleStyle(.button)
            .help(field.isConcealed ? "Concealed until revealed" : "Shown")
            .accessibilityLabel("Concealed")
        }
        .onChange(of: field.kind) { old, new in
            if old.isConcealedByDefault != new.isConcealedByDefault { field.isConcealed = new.isConcealedByDefault }
        }
    }
}

/// A grid of the group icons to choose from.
struct IconGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(GroupIcons.all, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .frame(width: 32, height: 32)
                        .background(
                            selection == icon ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 7)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(selection == icon ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

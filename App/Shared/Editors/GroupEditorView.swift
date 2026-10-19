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
                        .reorderable(field, in: $draft.fields, title: field.label)
                }
                .onDelete { draft.fields.remove(atOffsets: $0) }
                #if os(iOS)
                    .onMove { draft.fields.move(fromOffsets: $0, toOffset: $1) }
                #endif
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
            LabelField(label: $field.label)
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
            Toggle(isOn: $field.isMonospaced) {
                Image(systemName: "character.textbox")
            }
            .toggleStyle(.button)
            .help(field.isMonospaced ? "Value shown in a monospaced font" : "Value shown in the standard font")
            .accessibilityLabel("Monospaced")
        }
        .onChange(of: field.kind) { old, new in
            if old.isConcealedByDefault != new.isConcealedByDefault {
                field.isConcealed = new.isConcealedByDefault
                field.isMonospaced = new.isMonospacedByDefault(isConcealed: field.isConcealed)
            }
        }
    }
}

/// A field's editable label. A long label wraps onto more lines, up to three, so it can be read
/// whole while editing; a line break typed or pasted into it becomes a space.
struct LabelField: View {
    @Binding var label: String

    var body: some View {
        TextField("Label", text: $label, prompt: Text("Label"), axis: .vertical)
            .lineLimit(1...3)
            .labelsHidden()
            .onChange(of: label) {
                if label.contains(where: \.isNewline) {
                    label = label.split(whereSeparator: \.isNewline).joined(separator: " ")
                }
            }
    }
}

/// A grid of the group icons to choose from.
struct IconGrid: View {
    @Binding var selection: String

    var body: some View {
        WrappingLayout(spacing: 6) {
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

/// Lays its subviews out in rows, left to right, wrapping at the proposed width.
///
/// The icon grid used an adaptive `LazyVGrid`, but in a form row on iPad it was measured at a
/// narrow width (one icon per row) and drawn at the full one, which left a row about 1,500
/// points tall that pushed the Fields section off screen. This layout reports the height of the
/// rows it actually draws.
struct WrappingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

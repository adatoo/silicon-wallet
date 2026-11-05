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
    /// The related entries, as `VaultSession.relatedEntries(of:)` lists them, in the order shown.
    @State private var related: [VaultEntry] = []
    /// The IDs in `related` when the editor opened, so Save only relinks if they changed.
    @State private var originalRelatedIDs: [UUID]?
    @State private var pickingRelated = false
    /// A card scan that found values different from ones already filled in, while Save asks
    /// whether to replace them.
    @State private var pendingScan: PendingScan?

    private struct PendingScan {
        let card: ScannedCard
        let labels: [String]
    }
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
                    if hasCardField(.number), CardScanButtons.isAvailable {
                        CardScanButtons(
                            cardNumber: cardValue(.number), canScanBack: hasCardField(.securityCode),
                            onScanned: scanned)
                    }
                    ForEach(group.fields) { field in
                        FieldInput(
                            label: field.label, kind: field.kind, isConcealed: field.isConcealed,
                            isMonospaced: field.isMonospaced, value: valueBinding(field.id),
                            isCardNumber: PaymentCard.isCardNumberLabel(field.label),
                            isSortCode: SortCode.isSortCodeLabel(field.label))
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

            Section {
                ForEach(related) { entry in
                    HStack {
                        RelatedEntryLabel(entry: entry)
                        Spacer()
                        Button("Remove Related Entry", systemImage: "minus.circle.fill", role: .destructive) {
                            related.removeAll { $0.id == entry.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Unlink \(entry.title) when you save")
                    }
                    .reorderable(entry, in: $related, title: entry.title)
                }
                #if os(iOS)
                    .onMove { related.move(fromOffsets: $0, toOffset: $1) }
                #endif
                Button("Add Related Entry…", systemImage: "link") { pickingRelated = true }
            } header: {
                Text("Related")
            } footer: {
                Text("Entries that go with this one, such as a bank's login and its accounts. Each shows on the other.")
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
            if originalRelatedIDs == nil {
                related = isNew ? [] : (model.session?.relatedEntries(of: draft.id) ?? [])
                originalRelatedIDs = related.map(\.id)
            }
        }
        .confirmationDialog(
            "Replace \(pendingScan?.labels.formatted(.list(type: .and)) ?? "")?",
            isPresented: Binding(get: { pendingScan != nil }, set: { if !$0 { pendingScan = nil } }),
            titleVisibility: .visible, presenting: pendingScan
        ) { pending in
            Button("Replace") { fill(from: pending.card, replacing: true) }
            Button("Keep Current", role: .cancel) {}
        } message: { _ in
            Text("The scan read something different. What's there now stays unless you replace it.")
        }
        .sheet(isPresented: $pickingRelated) {
            RelatedEntryPicker(excluded: Set(related.map(\.id) + [draft.id])) { related.append($0) }
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
        let removals = original.map { draft.removals(since: $0, in: group) }
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

    // MARK: - Card scans (ADR-0009)

    /// The template and extra fields that a scan can fill, with their current values.
    private var cardFields: [(kind: CardField, label: String, value: String)] {
        let template = (group?.fields ?? []).compactMap { field in
            CardField(label: field.label).map { ($0, field.label, draft.values[field.id] ?? "") }
        }
        let extra = draft.extraFields.compactMap { field in
            CardField(label: field.label).map { ($0, field.label, field.value) }
        }
        return template + extra
    }

    private func hasCardField(_ kind: CardField) -> Bool { cardFields.contains { $0.kind == kind } }

    private func cardValue(_ kind: CardField) -> String? {
        cardFields.first { $0.kind == kind && !$0.value.isEmpty }?.value
    }

    /// Fills the empty fields a scan found values for, then asks before replacing any others.
    private func scanned(_ card: ScannedCard) {
        let clashes = cardFields.filter { field in
            guard let value = field.kind.value(in: card), !field.value.isEmpty else { return false }
            return Self.comparable(field.value) != Self.comparable(value)
        }
        fill(from: card, replacing: false)
        guard !clashes.isEmpty else { return }
        let pending = PendingScan(card: card, labels: clashes.map(\.label))
        // After the scanner has gone, so the question isn't lost in its dismissal.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            pendingScan = pending
        }
    }

    private func fill(from card: ScannedCard, replacing: Bool) {
        for field in group?.fields ?? [] {
            guard let kind = CardField(label: field.label), let value = kind.value(in: card) else { continue }
            if replacing || (draft.values[field.id] ?? "").isEmpty { draft.values[field.id] = value }
        }
        for index in draft.extraFields.indices {
            guard let kind = CardField(label: draft.extraFields[index].label), let value = kind.value(in: card)
            else { continue }
            if replacing || draft.extraFields[index].value.isEmpty { draft.extraFields[index].value = value }
        }
    }

    /// A value without spacing or case, so "4111111111111111" matches "4111 1111 1111 1111".
    private static func comparable(_ value: String) -> String {
        value.filter { !$0.isWhitespace }.uppercased()
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
            let relatedIDs = related.map(\.id)
            if isNew {
                entry.relatedIDs = relatedIDs
                let saved = try session.addEntry(entry)
                model.entrySelection = saved.id
            } else {
                try session.updateEntry(entry, related: relatedIDs == originalRelatedIDs ? nil : relatedIDs)
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
    /// Shows the card's scheme and warns when a full number fails its check digit.
    var isCardNumber = false
    /// Writes six digits as `12-34-56` once they're typed or pasted.
    var isSortCode = false
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
                    VStack(alignment: .leading, spacing: 4) {
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
                            if isCardNumber, let scheme = PaymentCard.scheme(for: value) {
                                CardSchemeBadge(scheme: scheme)
                            }
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
                        // Only a warning: Save still works.
                        if isCardNumber, PaymentCard.failsCheckDigit(value) {
                            Label(
                                "This number doesn't pass the card check digit; check for a typo.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
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
            } else if isSortCode, let formatted = SortCode.formatted(new), formatted != new {
                value = formatted
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
                value: $field.value, isCardNumber: PaymentCard.isCardNumberLabel(field.label),
                isSortCode: SortCode.isSortCodeLabel(field.label))
        }
        .onChange(of: field.kind) { old, new in
            if old.isConcealedByDefault != new.isConcealedByDefault {
                field.isConcealed = new.isConcealedByDefault
                field.isMonospaced = new.isMonospacedByDefault(isConcealed: field.isConcealed)
            }
        }
    }
}

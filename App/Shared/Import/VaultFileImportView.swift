import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports a Silicon Wallet backup or JSON export (ADR-0008): choose the file, enter a backup's
/// export password, check what's new, import. Groups and entries the vault already has are left
/// alone, so importing the same file twice adds nothing. The file is read into memory only.
struct VaultFileImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case choose
        case password(filename: String, contents: Data)
        case preview(filename: String, kind: ExportFile.Kind, plan: VaultImportPlan, summary: ImportSummary)
        case done(kind: ExportFile.Kind, summary: ImportSummary)
    }

    @State private var stage = Stage.choose
    @State private var choosingFile = false
    @State private var password = ""
    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        Form {
            switch stage {
            case .choose: chooseSection
            case .password(let filename, _): passwordSection(filename)
            case .preview(let filename, _, _, let summary): previewSection(filename, summary)
            case .done(let kind, let summary): doneSection(kind, summary)
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Import")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .frame(minWidth: 520, minHeight: 420)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if case .done = stage {
                    EmptyView()
                } else {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) { confirmButton }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.siliconWalletBackup, .json]) { result in
            load(result)
        }
        .onDisappear {
            password = ""
            stage = .choose
        }
    }

    // MARK: - Stages

    private var chooseSection: some View {
        Section {
            Text(
                "Import a Silicon Wallet backup, or a JSON export from Silicon Wallet. Anything already in this vault is left as it is."
            )
            Button("Choose File…", systemImage: "doc.badge.plus") { choosingFile = true }
        } footer: {
            Text("To import from Acrylic Wallet, use Import from Acrylic Wallet instead.")
        }
    }

    private func passwordSection(_ filename: String) -> some View {
        Section {
            LabeledContent("File", value: filename)
            SecureField("Export password", text: $password)
                .textContentType(.password)
                .onSubmit(decrypt)
        } footer: {
            Text("The password chosen when the backup was made. It may differ from your master password.")
        }
    }

    private func previewSection(_ filename: String, _ summary: ImportSummary) -> some View {
        Section {
            LabeledContent("File", value: filename)
            LabeledContent("New groups", value: "\(summary.groups)")
            LabeledContent("New entries", value: "\(summary.entries)")
            LabeledContent("Attachments", value: "\(summary.attachments)")
            if summary.entriesAlreadyHere > 0 || summary.groupsAlreadyHere > 0 {
                Text(
                    "\(summary.entriesAlreadyHere) entries and \(summary.groupsAlreadyHere) groups are already in this vault, so they'll be left as they are."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
            if summary.restoredGroups > 0 {
                Text("\(summary.restoredGroups) groups will come back from Recently Deleted to hold new entries.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if summary.entriesWithoutGroup > 0 {
                Text("\(summary.entriesWithoutGroup) entries have no group in the file, so they won't be imported.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if case .preview(_, _, let plan, _) = stage, plan.leftOutAttachmentCount > 0 {
                Text(
                    "\(plan.leftOutAttachmentCount) attachments are missing from the file or over \(VaultSession.maximumAttachmentSize.formatted(.byteCount(style: .file))), so they won't be imported."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(summary.entries + summary.groups == 0 ? "Nothing New to Import" : "Ready to Import")
        }
    }

    private func doneSection(_ kind: ExportFile.Kind, _ summary: ImportSummary) -> some View {
        Section {
            Label(
                "Imported \(summary.entries) entries and \(summary.groups) groups, with \(summary.attachments) attachments.",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            if kind == .json {
                Text("The JSON file isn't encrypted. Delete it once you've checked your entries.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        if isWorking {
            ProgressView().controlSize(.small)
        } else {
            switch stage {
            case .choose: EmptyView()
            case .password: Button("Continue", action: decrypt).disabled(password.isEmpty)
            case .preview(_, let kind, let plan, let summary):
                Button("Import") { importPlan(plan, kind: kind) }
                    .disabled(summary.entries + summary.groups == 0)
            case .done: Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Actions

    private func load(_ result: Result<URL, Error>) {
        problem = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ExportFile.maximumFileSize {
                problem = Self.tooLargeMessage
                return
            }
            let contents = try Data(contentsOf: url)
            switch ExportFile.kind(of: contents) {
            case .backup:
                stage = .password(filename: url.lastPathComponent, contents: contents)
            case .json:
                makePlan(filename: url.lastPathComponent, kind: .json) { try ExportFile.plan(json: contents) }
            case nil:
                problem = Self.message(for: ExportFileError.notAnExport)
            }
        } catch {
            problem = "That file couldn't be read: \(error.localizedDescription)"
        }
    }

    private func decrypt() {
        guard case .password(let filename, let contents) = stage, !password.isEmpty, !isWorking else { return }
        let password = password
        makePlan(filename: filename, kind: .backup) { try ExportFile.plan(backup: contents, password: password) }
    }

    /// Reads the file off the main actor (a backup runs Argon2id), then previews what's new.
    private func makePlan(
        filename: String, kind: ExportFile.Kind, _ read: @escaping @Sendable () throws -> VaultImportPlan
    ) {
        isWorking = true
        problem = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try read() } }.value
            isWorking = false
            do {
                let plan = try result.get()
                guard let session = model.session else { return }
                password = ""
                stage = .preview(
                    filename: filename, kind: kind, plan: plan, summary: try session.importPreview(plan))
            } catch {
                problem = Self.message(for: error)
            }
        }
    }

    private func importPlan(_ plan: VaultImportPlan, kind: ExportFile.Kind) {
        guard let session = model.session else { return }
        do {
            let summary = try session.importItems(plan)
            stage = .done(kind: kind, summary: summary)
            model.sidebarSelection = .all
        } catch {
            problem = AppModel.describe(error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case ExportFileError.notAnExport:
            "This isn't a Silicon Wallet backup or JSON export."
        case ExportFileError.unsupportedVersion:
            "This file was made by a newer version of Silicon Wallet. Update the app, then try again."
        case ExportFileError.wrongPasswordOrDamaged:
            "That password didn't open the backup. Check it's the export password chosen when the backup was made."
        case ExportFileError.damaged:
            "The file is damaged or has been changed, so nothing was imported."
        case ExportFileError.fileTooLarge:
            tooLargeMessage
        default:
            AppModel.describe(error)
        }
    }

    private static let tooLargeMessage =
        "That file is larger than \(ExportFile.maximumFileSize.formatted(.byteCount(style: .file))), the most Silicon Wallet can import."
}

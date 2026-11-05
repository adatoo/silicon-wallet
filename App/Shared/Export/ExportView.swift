import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A Silicon Wallet backup file (ADR-0008). Declared in `project.yml`.
    static let siliconWalletBackup = UTType(exportedAs: "com.datoos.silicon-wallet.backup")
}

/// Exports the vault (ADR-0008, DESIGN.md §9): a Silicon Wallet backup sealed under an export
/// password, or plaintext JSON. Both need the master password. The file is made in memory and
/// handed to the save panel; nothing is written anywhere else.
struct ExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Format: String, CaseIterable, Identifiable {
        case backup
        case json

        var id: Self { self }

        var title: String {
            switch self {
            case .backup: "Silicon Wallet Backup (encrypted)"
            case .json: "JSON (not encrypted)"
            }
        }
    }

    @State private var format = Format.backup
    @State private var masterPassword = ""
    @State private var exportPassword = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var problem: String?
    @State private var file: ExportedFile?
    @State private var exporting = false
    @State private var savedSummary: String?

    var body: some View {
        Form {
            if let savedSummary {
                doneSection(savedSummary)
            } else {
                formatSection
                Section {
                    SecureField("Master password", text: $masterPassword)
                        .textContentType(.password)
                } header: {
                    Text("Master Password")
                } footer: {
                    Text("Exporting needs your master password.")
                }
                switch format {
                case .backup: exportPasswordSection
                case .json: jsonWarningSection
                }
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export Vault")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .frame(minWidth: 520, minHeight: 460)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if savedSummary == nil {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) { confirmButton }
        }
        .fileExporter(
            isPresented: $exporting, document: file, contentType: file?.contentType ?? .data,
            defaultFilename: file?.filename
        ) { result in
            finishSaving(result)
        }
        .onChange(of: format) { problem = nil }
        .onDisappear(perform: forget)
    }

    // MARK: - Sections

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $format) {
                ForEach(Format.allCases) { Text($0.title).tag($0) }
            }
            #if os(iOS)
                .pickerStyle(.inline)
                .labelsHidden()
            #else
                .pickerStyle(.radioGroup)
            #endif
        } header: {
            Text("Format")
        } footer: {
            switch format {
            case .backup:
                Text(
                    "Everything in your vault, with attachments, encrypted with a password you choose. Import it into Silicon Wallet on any device."
                )
            case .json:
                Text(
                    "Everything in your vault, with attachments, as readable text. Use it to move to another app or keep a copy you can read without Silicon Wallet."
                )
            }
        }
    }

    private var exportPasswordSection: some View {
        Section {
            SecureField("Export password", text: $exportPassword)
                .textContentType(.newPassword)
            SecureField("Confirm export password", text: $confirmation)
                .textContentType(.newPassword)
            PasswordStrengthView(password: exportPassword)
        } header: {
            Text("Export Password")
        } footer: {
            Text(
                "You'll need this password to import the backup. It can differ from your master password, and it can't be recovered, so keep it somewhere safe."
            )
        }
    }

    private var jsonWarningSection: some View {
        Section {
            Label(
                "A JSON export isn't encrypted. Anyone who gets the file can read every password, card number and note in it, and open its attachments.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            Text("Keep it off cloud storage and shared folders, and delete it as soon as you've finished with it.")
                .foregroundStyle(.secondary)
        }
    }

    private func doneSection(_ summary: String) -> some View {
        Section {
            Label(summary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if format == .json {
                Text("This file isn't encrypted. Delete it, and empty the Bin, once you've finished with it.")
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    "Keep the backup and its export password apart: anyone with both can read it. Without the password, nobody can open it, including you."
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        if isWorking {
            ProgressView().controlSize(.small)
        } else if savedSummary != nil {
            Button("Done") { dismiss() }
        } else {
            Button("Export…", action: export).disabled(inputProblem != nil)
        }
    }

    /// Why Export can't run yet, if it can't.
    private var inputProblem: String? {
        if masterPassword.isEmpty { return "Enter your master password." }
        guard format == .backup else { return nil }
        if exportPassword.count < SetupView.minimumLength {
            return "Use at least \(SetupView.minimumLength) characters for the export password."
        }
        if exportPassword != confirmation { return "The export passwords don't match." }
        return nil
    }

    // MARK: - Actions

    private func export() {
        guard inputProblem == nil, !isWorking, let session = model.session else { return }
        isWorking = true
        problem = nil
        let format = format
        let exportPassword = exportPassword
        Task {
            defer { isWorking = false }
            do {
                guard try await session.verifyPassword(masterPassword) else {
                    problem = "That master password is wrong."
                    return
                }
                let contents: Data
                switch format {
                case .backup: contents = try await session.exportBackup(password: exportPassword)
                case .json: contents = try session.exportJSON()
                }
                file = ExportedFile(
                    contents: contents, format: format, entryCount: session.entries.count,
                    groupCount: session.groups.count)
                exporting = true
            } catch {
                problem = AppModel.describe(error)
            }
        }
    }

    private func finishSaving(_ result: Result<URL, Error>) {
        guard let file else { return }
        switch result {
        case .success:
            let detail =
                "\(file.format == .backup ? "Silicon Wallet backup" : "JSON, not encrypted"): \(file.entryCount) entries, \(file.groupCount) groups"
            model.session?.recordAccess(.vaultExported, detail: detail)
            savedSummary = "Exported \(file.entryCount) entries in \(file.groupCount) groups."
            forget()
        case .failure(let error):
            problem = "The file couldn't be saved: \(error.localizedDescription)"
        }
    }

    /// Drops the passwords and the file's contents from memory.
    private func forget() {
        masterPassword = ""
        exportPassword = ""
        confirmation = ""
        file = nil
    }
}

/// An export handed to the save panel.
struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.siliconWalletBackup, .json]
    static let writableContentTypes: [UTType] = [.siliconWalletBackup, .json]

    let contents: Data
    let format: ExportView.Format
    let entryCount: Int
    let groupCount: Int

    var contentType: UTType { format == .backup ? .siliconWalletBackup : .json }

    /// "Silicon Wallet 2026-11-05".
    var filename: String { "Silicon Wallet \(Date.now.formatted(.iso8601.year().month().day()))" }

    init(contents: Data, format: ExportView.Format, entryCount: Int, groupCount: Int) {
        self.contents = contents
        self.format = format
        self.entryCount = entryCount
        self.groupCount = groupCount
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

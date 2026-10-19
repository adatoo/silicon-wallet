import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports an Acrylic Wallet `.wallet` file: choose it, enter its password, check the preview,
/// import. The file is read once into memory and never written anywhere (DESIGN.md §5, §9).
struct AcrylicImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case choose
        case password(filename: String, ciphertext: Data)
        case preview(filename: String, plan: AcrylicImportPlan)
        case done(groups: Int, entries: Int, attachments: Int)
    }

    @State private var stage = Stage.choose
    @State private var choosingFile = false
    @State private var password = ""
    @State private var isWorking = false
    @State private var problem: String?

    static let walletType = UTType(filenameExtension: "wallet") ?? .data

    var body: some View {
        Form {
            switch stage {
            case .choose: chooseSection
            case .password(let filename, _): passwordSection(filename)
            case .preview(let filename, let plan): previewSection(filename, plan)
            case .done(let groups, let entries, let attachments): doneSection(groups, entries, attachments)
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Import from Acrylic Wallet")
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
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [Self.walletType, .data]) { result in
            load(result)
        }
        .onDisappear { password = "" }
    }

    // MARK: - Stages

    private var chooseSection: some View {
        Section {
            Text(
                "Silicon Wallet reads your Acrylic Wallet vault directly. You don't need Wallet installed, and nothing is uploaded or saved unencrypted."
            )
            Button("Choose Wallet File…", systemImage: "doc.badge.plus") { choosingFile = true }
        } footer: {
            #if os(macOS)
                Text(
                    "Wallet keeps its vault at ~/Library/Containers/com.acrylic.WalletMac/Data/Library/Application Support/Wallet/Database.wallet. In the file picker, press ⇧⌘G and paste that path. A Dropbox copy or a \"Wallet Database\" export works too."
                )
            #else
                Text("Put your Database.wallet file, or a Wallet Database export, in the Files app first.")
            #endif
        }
    }

    private func passwordSection(_ filename: String) -> some View {
        Section {
            LabeledContent("File", value: filename)
            SecureField("Acrylic Wallet password", text: $password)
                .textContentType(.password)
                .onSubmit(decrypt)
        } footer: {
            Text("This is your old Wallet password, not your Silicon Wallet master password.")
        }
    }

    private func previewSection(_ filename: String, _ plan: AcrylicImportPlan) -> some View {
        Group {
            Section("Ready to Import") {
                LabeledContent("Groups", value: "\(plan.groups.count)")
                LabeledContent("Entries", value: "\(plan.entries.count)")
                LabeledContent("Fields", value: "\(plan.fieldCount)")
                LabeledContent("Attachments", value: "\(plan.attachments.count)")
                if plan.unlabelledValueCount > 0 {
                    Text(
                        "\(plan.unlabelledValueCount) values had no label in Wallet; they're kept as extra fields called \"Field\"."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                if plan.missingAttachmentCount > 0 {
                    Text("\(plan.missingAttachmentCount) attachments were listed but missing from the file.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Groups") {
                ForEach(plan.groups) { group in
                    let count = plan.entries.filter { $0.groupID == group.id }.count
                    Label(group.name, systemImage: group.icon).badge(count)
                }
            }
        }
    }

    private func doneSection(_ groups: Int, _ entries: Int, _ attachments: Int) -> some View {
        Section {
            Label(
                "Imported \(entries) entries in \(groups) groups, with \(attachments) attachments.",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            Text(
                "Check a few entries, then delete the old file, any Dropbox copy and any Wallet exports. Silicon Wallet doesn't change or delete them."
            )
            .foregroundStyle(.secondary)
            Text(
                "Wallet's encryption is weak by today's standards: anyone with a copy of an old file can try passwords against it very quickly. Deleting old copies keeps your secrets safe."
            )
            .font(.footnote).foregroundStyle(.secondary)
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
            case .preview(_, let plan): Button("Import") { importPlan(plan) }
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
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            stage = .password(filename: url.lastPathComponent, ciphertext: Data(data))
        } catch {
            problem = "That file couldn't be read: \(error.localizedDescription)"
        }
    }

    private func decrypt() {
        guard case .password(let filename, let ciphertext) = stage, !password.isEmpty, !isWorking else { return }
        isWorking = true
        problem = nil
        let password = password
        let existing = Set(model.session?.groups.map(\.name) ?? [])
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try AcrylicImporter.plan(ciphertext: ciphertext, password: password, existingGroupNames: existing)
                }
            }.value
            isWorking = false
            switch result {
            case .success(let plan):
                self.password = ""
                stage = .preview(filename: filename, plan: plan)
            case .failure(AcrylicWalletError.wrongPasswordOrUnsupportedFile):
                problem = "That password didn't open the file. Check it, and that this is an Acrylic Wallet 3 file."
            case .failure(AcrylicWalletError.notAnAcrylicWallet):
                problem = "This doesn't look like an Acrylic Wallet file."
            case .failure(AcrylicWalletError.unsupportedFormat):
                problem =
                    "This Wallet file uses a format Silicon Wallet can't read yet. Please report it on the project's GitHub page, without attaching the file."
            case .failure:
                problem = "The file opened but looks damaged, so nothing was imported."
            }
        }
    }

    private func importPlan(_ plan: AcrylicImportPlan) {
        guard let session = model.session else { return }
        do {
            let counts = try session.importItems(plan)
            stage = .done(groups: counts.groups, entries: counts.entries, attachments: counts.attachments)
            model.sidebarSelection = .all
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

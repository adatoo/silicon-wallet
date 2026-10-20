import PhotosUI
import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

/// What the attachments section has asked to present: a preview, the file importer or a
/// removal confirmation.
struct AttachmentPresentation {
    var previewing: OpenedAttachment?
    var addingFiles = false
    var toRemove: AttachmentRef?
}

/// The detail view's attachments: open, add, remove (DESIGN.md §4, §7).
///
/// Its sheet, file importer and confirmation are attached once, to the whole form, with
/// `attachmentPresentations(for:_:)`. A modifier on a `Section` applies to each of its rows, so
/// a sheet attached to it is presented once per row and dismisses itself straight away on iOS.
struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    @Binding var presentation: AttachmentPresentation
    /// For an entry in Recently Deleted: attachments open and save, but can't be added or removed.
    var isReadOnly = false

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isDropTargeted = false

    var body: some View {
        Section {
            ForEach(entry.attachments) { attachment in
                Button {
                    presentation.previewing = OpenedAttachment(attachment, session: model.session)
                } label: {
                    AttachmentRow(
                        attachment: attachment, isAvailable: model.session?.isAttachmentAvailable(attachment) ?? false)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open", systemImage: "eye") {
                        presentation.previewing = OpenedAttachment(attachment, session: model.session)
                    }
                    if !isReadOnly {
                        Button("Remove…", systemImage: "trash", role: .destructive) {
                            presentation.toRemove = attachment
                        }
                    }
                }
                .swipeActions {
                    if !isReadOnly {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            presentation.toRemove = attachment
                        }
                    }
                }
            }
            if !isReadOnly {
                addButtons
            }
        } header: {
            Text("Attachments")
        } footer: {
            if !isReadOnly {
                #if os(macOS)
                    Text("You can also drop files here. Each attachment is encrypted with its own key, up to 100 MB.")
                #else
                    Text("Each attachment is encrypted with its own key, up to 100 MB.")
                #endif
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isReadOnly else { return false }
            Self.add(urls, to: entry.id, model: model)
            return true
        } isTargeted: {
            isDropTargeted = $0 && !isReadOnly
        }
        .listRowBackground(isDropTargeted ? Color.accentColor.opacity(0.15) : nil)
    }

    private var addButtons: some View {
        HStack {
            Button("Add File…", systemImage: "doc.badge.plus") { presentation.addingFiles = true }
            #if os(iOS)
                PhotosPicker(selection: $photoItems, matching: .images) {
                    Label("Add Photo…", systemImage: "photo.badge.plus")
                }
                .onChange(of: photoItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await addPhotos(items) }
                }
            #endif
        }
        .buttonStyle(.borderless)
    }

    /// Attaches each file to the entry, reporting any that can't be added.
    static func add(_ urls: [URL], to entryID: VaultEntry.ID, model: AppModel) {
        guard let session = model.session else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
                guard values.isDirectory != true else { continue }
                if let size = values.fileSize, size > VaultSession.maximumAttachmentSize {
                    throw VaultError.attachmentTooLarge
                }
                let contents = try Data(contentsOf: url)
                try session.addAttachment(
                    to: entryID, filename: url.lastPathComponent,
                    uti: (values.contentType ?? .data).identifier, contents: contents)
            } catch VaultError.attachmentTooLarge {
                model.errorMessage = "\(url.lastPathComponent) is larger than 100 MB, so it can't be attached."
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        guard let session = model.session else { return }
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first ?? .jpeg
                let name = "Photo \(index + 1).\(type.preferredFilenameExtension ?? "jpg")"
                try session.addAttachment(to: entry.id, filename: name, uti: type.identifier, contents: data)
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}

extension View {
    /// Presents what an `AttachmentsSection` asks for. Apply it once, to the form holding the
    /// section, never to the section itself.
    func attachmentPresentations(for entry: VaultEntry, _ presentation: Binding<AttachmentPresentation>) -> some View {
        modifier(AttachmentPresentations(entry: entry, presentation: presentation))
    }
}

private struct AttachmentPresentations: ViewModifier {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry
    @Binding var presentation: AttachmentPresentation

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $presentation.addingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { AttachmentsSection.add(urls, to: entry.id, model: model) }
            }
            .sheet(item: $presentation.previewing) { opened in
                NavigationStack { AttachmentPreviewView(opened: opened) }
                    #if os(macOS)
                        // Opens at the preview's ideal size (the whole image, within the
                        // screen) and can be resized.
                        .presentationSizing(.fitted)
                    #else
                        .presentationSizing(.page)
                    #endif
            }
            .confirmationDialog(
                "Remove \(presentation.toRemove?.filename ?? "this attachment")?",
                isPresented: Binding(
                    get: { presentation.toRemove != nil }, set: { if !$0 { presentation.toRemove = nil } }),
                titleVisibility: .visible,
                presenting: presentation.toRemove
            ) { attachment in
                Button("Remove Attachment", role: .destructive) {
                    model.perform { try model.session?.removeAttachment(id: attachment.id, from: entry.id) }
                }
            } message: { _ in
                Text("It will be deleted from this vault on all your devices.")
            }
    }
}

/// An attachment's name, size and, while syncing, whether it's on this device yet.
struct AttachmentRow: View {
    let attachment: AttachmentRef
    let isAvailable: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(attachment.filename)
                Text(isAvailable ? attachment.size.formatted(.byteCount(style: .file)) : "Waiting for iCloud…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
        .contentShape(.rect)
    }

    private var icon: String {
        switch AttachmentKind(uti: attachment.uti) {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .other: "paperclip"
        }
    }
}

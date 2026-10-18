import PhotosUI
import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

/// The detail view's attachments: open, add, remove (DESIGN.md §4, §7).
struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    let entry: VaultEntry

    @State private var previewing: AttachmentRef?
    @State private var addingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var toRemove: AttachmentRef?
    @State private var isDropTargeted = false

    var body: some View {
        Section {
            ForEach(entry.attachments) { attachment in
                Button {
                    previewing = attachment
                } label: {
                    AttachmentRow(
                        attachment: attachment, isAvailable: model.session?.isAttachmentAvailable(attachment) ?? false)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open", systemImage: "eye") { previewing = attachment }
                    Button("Remove…", systemImage: "trash", role: .destructive) { toRemove = attachment }
                }
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) { toRemove = attachment }
                }
            }
            HStack {
                Button("Add File…", systemImage: "doc.badge.plus") { addingFiles = true }
                #if os(iOS)
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Add Photo…", systemImage: "photo.badge.plus")
                    }
                #endif
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Attachments")
        } footer: {
            #if os(macOS)
                Text("You can also drop files here. Each attachment is encrypted with its own key, up to 100 MB.")
            #else
                Text("Each attachment is encrypted with its own key, up to 100 MB.")
            #endif
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .listRowBackground(isDropTargeted ? Color.accentColor.opacity(0.15) : nil)
        .fileImporter(isPresented: $addingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            result in
            if case .success(let urls) = result { add(urls) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .sheet(item: $previewing) { attachment in
            NavigationStack { AttachmentPreviewView(attachment: attachment) }
        }
        .confirmationDialog(
            "Remove \(toRemove?.filename ?? "this attachment")?",
            isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
            titleVisibility: .visible,
            presenting: toRemove
        ) { attachment in
            Button("Remove Attachment", role: .destructive) {
                model.perform { try model.session?.removeAttachment(id: attachment.id, from: entry.id) }
            }
        } message: { _ in
            Text("It will be deleted from this vault on all your devices.")
        }
    }

    private func add(_ urls: [URL]) {
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
                    to: entry.id, filename: url.lastPathComponent,
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

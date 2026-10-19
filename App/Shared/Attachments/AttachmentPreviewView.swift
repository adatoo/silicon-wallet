import PDFKit
import QuickLook
import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// How an attachment can be shown. Images, PDFs and text are shown from memory; anything else
/// needs Quick Look and a temporary decrypted file.
enum AttachmentKind: Equatable {
    case image
    case pdf
    case text
    case other

    init(uti: String) {
        let type = UTType(uti) ?? .data
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .plainText) || type.conforms(to: .json) || type.conforms(to: .xml) {
            self = .text
        } else {
            self = .other
        }
    }
}

/// Decrypted files for Quick Look. They live in one temporary folder, with complete file
/// protection on iOS, and are deleted when a preview closes, when the vault locks and at launch
/// (DESIGN.md §5).
@MainActor
enum TemporaryPreviews {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Previews", isDirectory: true)
    }

    static func write(_ contents: Data, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sanitised = filename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let safeName = sanitised.isEmpty ? "Attachment" : sanitised
        let url = folder.appendingPathComponent(safeName)
        #if os(iOS)
            try contents.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try contents.write(to: url, options: .atomic)
        #endif
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Shows one attachment, decrypted in memory, with Save a Copy and Quick Look.
struct AttachmentPreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let attachment: AttachmentRef

    @State private var contents: Data?
    @State private var problem: String?
    @State private var quickLookURL: URL?
    @State private var exporting = false

    var body: some View {
        Group {
            if let problem {
                ContentUnavailableView(
                    "Can't Open \(attachment.filename)", systemImage: "paperclip", description: Text(problem))
            } else if let contents {
                preview(contents)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(attachment.filename)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .frame(minWidth: 520, minHeight: 420)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if contents != nil {
                    Button("Save a Copy…", systemImage: "square.and.arrow.down") { exporting = true }
                    if AttachmentKind(uti: attachment.uti) == .other {
                        Button("Quick Look", systemImage: "eye", action: openQuickLook)
                    }
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .onChange(of: quickLookURL) { old, new in
            if let old, new == nil { TemporaryPreviews.remove(old) }
        }
        // `.data`, not the attachment's own type: an exporter only uses types the document lists
        // as writable, and it lists `.data` alone. The filename keeps its extension.
        .fileExporter(
            isPresented: $exporting, document: AttachmentDocument(contents: contents ?? Data()),
            contentType: .data, defaultFilename: attachment.filename
        ) { result in
            switch result {
            case .success: model.session?.recordAccess(.exported, detail: attachment.filename)
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .task { load() }
        .onDisappear {
            contents = nil
            if let quickLookURL { TemporaryPreviews.remove(quickLookURL) }
        }
    }

    @ViewBuilder
    private func preview(_ contents: Data) -> some View {
        switch AttachmentKind(uti: attachment.uti) {
        case .image:
            if let image = PlatformImage(data: contents) {
                ScrollView([.horizontal, .vertical]) {
                    image.swiftUIImage
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: 300, minHeight: 300)
                        .accessibilityLabel(attachment.filename)
                }
            } else {
                fallback
            }
        case .pdf:
            PDFPreview(data: contents)
        case .text:
            ScrollView {
                Text(String(decoding: contents, as: UTF8.self))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        case .other:
            fallback
        }
    }

    private var fallback: some View {
        ContentUnavailableView {
            Label(attachment.filename, systemImage: "doc")
        } description: {
            Text(attachment.size.formatted(.byteCount(style: .file)))
        } actions: {
            Button("Quick Look", action: openQuickLook)
            Button("Save a Copy…") { exporting = true }
        }
    }

    private func load() {
        guard let session = model.session else { return }
        do {
            contents = try session.attachmentContents(attachment)
        } catch VaultError.attachmentUnavailable {
            problem = "It isn't on this device yet. It will appear once iCloud sync finishes."
        } catch {
            problem = AppModel.describe(error)
        }
    }

    private func openQuickLook() {
        guard let contents else { return }
        do {
            quickLookURL = try TemporaryPreviews.write(contents, filename: attachment.filename)
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The bytes handed to the save panel. Saving makes an unencrypted copy, which the panel's
/// caller warns about.
struct AttachmentDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let contents: Data

    init(contents: Data) { self.contents = contents }

    init(configuration: ReadConfiguration) throws {
        contents = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

#if os(iOS)
    typealias PlatformImage = UIImage
    extension UIImage {
        var swiftUIImage: Image { Image(uiImage: self) }
    }

    struct PDFPreview: UIViewRepresentable {
        let data: Data
        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(data: data)
            return view
        }
        func updateUIView(_ view: PDFView, context: Context) {}
    }
#else
    typealias PlatformImage = NSImage
    extension NSImage {
        var swiftUIImage: Image { Image(nsImage: self) }
    }

    struct PDFPreview: NSViewRepresentable {
        let data: Data
        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(data: data)
            return view
        }
        func updateNSView(_ view: PDFView, context: Context) {}
    }
#endif

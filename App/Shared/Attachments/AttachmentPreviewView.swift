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

/// An attachment decrypted for previewing. It's made when the attachment is opened, so the
/// preview knows the content's size before its sheet appears, and dropped when the sheet closes.
struct OpenedAttachment: Identifiable {
    let ref: AttachmentRef
    let contents: Data?
    let problem: String?
    let image: PlatformImage?
    let pdf: PDFDocument?

    var id: UUID { ref.id }
    var kind: AttachmentKind { AttachmentKind(uti: ref.uti) }

    /// The content's own size in points: an image's, or a PDF's first page.
    var naturalSize: CGSize? {
        if let image { return image.size }
        if let page = pdf?.page(at: 0) { return page.bounds(for: .mediaBox).size }
        return nil
    }

    @MainActor
    init(_ ref: AttachmentRef, session: VaultSession?) {
        self.ref = ref
        var contents: Data?
        var problem: String?
        do {
            guard let session else { throw VaultError.locked }
            contents = try session.attachmentContents(ref)
        } catch VaultError.attachmentUnavailable {
            problem = "It isn't on this device yet. It will appear once iCloud sync finishes."
        } catch {
            problem = AppModel.describe(error)
        }
        self.contents = contents
        self.problem = problem
        let kind = AttachmentKind(uti: ref.uti)
        image = kind == .image ? contents.flatMap(PlatformImage.init(data:)) : nil
        pdf = kind == .pdf ? contents.flatMap(PDFDocument.init(data:)) : nil
    }
}

/// Shows one attachment, decrypted in memory, with Save a Copy and Quick Look. Images and PDFs
/// open at their own size within the screen, and zoom.
struct AttachmentPreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let opened: OpenedAttachment

    @State private var exportProblem: String?
    @State private var quickLookURL: URL?
    @State private var exporting = false
    @State private var zoom = ZoomController()

    private var attachment: AttachmentRef { opened.ref }
    private var isZoomable: Bool { opened.image != nil || opened.pdf != nil }

    var body: some View {
        Group {
            if let problem = opened.problem ?? exportProblem {
                ContentUnavailableView(
                    "Can't Open \(attachment.filename)", systemImage: "paperclip", description: Text(problem))
            } else if let contents = opened.contents {
                preview(contents)
            }
        }
        .navigationTitle(attachment.filename)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #else
            .frame(
                minWidth: Self.minimumSize.width, idealWidth: idealSize.width, maxWidth: .infinity,
                minHeight: Self.minimumSize.height, idealHeight: idealSize.height, maxHeight: .infinity)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            #if os(iOS)
                if isZoomable {
                    ToolbarItemGroup(placement: .bottomBar) { zoomButtons }
                }
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(macOS)
                    if isZoomable { zoomButtons }
                #endif
                if opened.contents != nil {
                    Button("Save a Copy…", systemImage: "square.and.arrow.down") { exporting = true }
                    if opened.kind == .other {
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
            isPresented: $exporting, document: AttachmentDocument(contents: opened.contents ?? Data()),
            contentType: .data, defaultFilename: attachment.filename
        ) { result in
            switch result {
            case .success: model.session?.recordAccess(.exported, detail: attachment.filename)
            case .failure(let error): exportProblem = error.localizedDescription
            }
        }
        .onDisappear {
            if let quickLookURL { TemporaryPreviews.remove(quickLookURL) }
        }
    }

    @ViewBuilder
    private var zoomButtons: some View {
        Button("Zoom Out", systemImage: "minus.magnifyingglass", action: zoom.zoomOut)
            .keyboardShortcut("-")
            .help("Zoom out (⌘-)")
            .disabled(!zoom.canZoomOut)
        Button("Zoom In", systemImage: "plus.magnifyingglass", action: zoom.zoomIn)
            .keyboardShortcut("=")
            .help("Zoom in (⌘=)")
            .disabled(!zoom.canZoomIn)
        Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass", action: zoom.zoomToFit)
            .keyboardShortcut("9")
            .help("Zoom to fit (⌘9)")
            .disabled(zoom.isFitting)
        Button("Actual Size", systemImage: "1.magnifyingglass", action: zoom.actualSize)
            .keyboardShortcut("0")
            .help("Actual size (⌘0)")
            .disabled(zoom.isActualSize)
    }

    #if os(macOS)
        private static let minimumSize = CGSize(width: 520, height: 420)

        /// The whole image or page, scaled down to fit 90% of the screen below the toolbar.
        private var idealSize: CGSize {
            guard let natural = opened.naturalSize,
                let screen = NSApp.keyWindow?.screen ?? NSScreen.main
            else { return Self.minimumSize }
            let visible = screen.visibleFrame.size
            let available = CGSize(width: visible.width * 0.9, height: visible.height * 0.9 - 60)
            return PreviewGeometry.idealSize(content: natural, available: available, minimum: Self.minimumSize)
        }
    #endif

    @ViewBuilder
    private func preview(_ contents: Data) -> some View {
        switch opened.kind {
        case .image:
            if let image = opened.image {
                ZoomableImage(image: image, controller: zoom)
                    .accessibilityLabel(attachment.filename)
            } else {
                fallback
            }
        case .pdf:
            if let pdf = opened.pdf {
                PDFPreview(document: pdf, controller: zoom)
            } else {
                fallback
            }
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

    private func openQuickLook() {
        guard let contents = opened.contents else { return }
        do {
            quickLookURL = try TemporaryPreviews.write(contents, filename: attachment.filename)
        } catch {
            exportProblem = error.localizedDescription
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
#else
    typealias PlatformImage = NSImage
    extension NSImage {
        var swiftUIImage: Image { Image(nsImage: self) }
    }
#endif

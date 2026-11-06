import AVFoundation
import CoreImage
import SiliconWalletKit
import SwiftUI

/// Scans a card live with the camera, on this device (ADR-0009): the iPhone's back camera, or
/// on a Mac its own camera or a nearby iPhone as a Continuity Camera webcam. A card-shaped guide
/// shows where to hold it; the text read is outlined over the picture, and once the card's edge
/// is found, the edge too, and the frame is captured by itself when the same number (or, on the
/// back, code) reads twice. The shutter captures by hand; on a Mac, Take Photo with iPhone… is
/// there as well. The capture opens the review, to check and correct before Use. Frames and the
/// capture are only ever in memory.
struct LiveCardScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let side: CardScanSide
    let onUse: (ScannedCard) -> Void
    @State private var camera: CardCamera
    @State private var lines: [RecognisedLine] = []
    @State private var card = ScannedCard()

    init(side: CardScanSide, cardNumber: String?, onUse: @escaping (ScannedCard) -> Void) {
        self.side = side
        self.onUse = onUse
        _camera = State(initialValue: CardCamera(side: side, cardNumber: cardNumber))
    }

    static var isSupported: Bool { CardCamera.defaultCamera != nil }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(side == .front ? "Scan Card" : "Scan Back")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        #if os(macOS)
            .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 600)
        #endif
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capture?.id) {
            lines = camera.capture?.analysis.lines ?? []
            card = camera.capture?.analysis.card ?? ScannedCard()
        }
        .sensoryFeedback(.success, trigger: camera.capture?.id) { _, new in new != nil }
    }

    @ViewBuilder
    private var content: some View {
        if let capture = camera.capture {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CardScanReview(image: capture.image, side: side, lines: $lines, card: $card)
                    if card.isEmpty { nothingFound }
                }
                .padding()
            }
        } else if case .unavailable(let message) = camera.state {
            ContentUnavailableView {
                Label("Camera Unavailable", systemImage: "camera")
            } description: {
                Text(message)
            } actions: {
                photoButton
            }
        } else {
            live
        }
    }

    private var nothingFound: some View {
        Text(
            side == .front
                ? "Nothing found yet. Choose text on the card, or try again with the front of the card filling the picture, in good light."
                : "Nothing found yet. Choose the code on the card, or try again with the signature strip in view, in good light."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if camera.capture != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") {
                    onUse(card)
                    dismiss()
                }
                .disabled(card.isEmpty)
            }
            ToolbarItem(placement: Self.retakePlacement) {
                Button("Retake", systemImage: "arrow.counterclockwise") { camera.retake() }
                    .labelStyle(.titleAndIcon)
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                if camera.cameras.count > 1 { cameraMenu }
                if camera.hasTorch {
                    Button(
                        camera.isTorchOn ? "Turn Torch Off" : "Turn Torch On",
                        systemImage: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                    ) { camera.toggleTorch() }
                }
            }
        }
    }

    #if os(iOS)
        private static let retakePlacement = ToolbarItemPlacement.bottomBar
    #else
        private static let retakePlacement = ToolbarItemPlacement.primaryAction
    #endif

    private var cameraMenu: some View {
        Menu("Camera", systemImage: "camera.on.rectangle") {
            Picker(
                "Camera",
                selection: Binding(get: { camera.cameraID }, set: { id in if let id { camera.select(cameraID: id) } })
            ) {
                ForEach(camera.cameras) { choice in
                    Text(choice.name).tag(Optional(choice.id))
                }
            }
            .pickerStyle(.inline)
        }
        .help("Choose the camera")
    }

    /// Continuity Camera's Take Photo and Scan Documents, from a nearby iPhone or iPad: for a Mac
    /// with no camera, or when the iPhone's own camera app does better.
    @ViewBuilder
    private var photoButton: some View {
        #if os(macOS)
            ContinuityCameraButton(title: "Take Photo with iPhone…") { camera.use(photo: $0) }
                .fixedSize()
        #endif
    }

    private var live: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session, rotation: camera.rotation)
                .ignoresSafeArea()
            CardOverlay(analysis: camera.live)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        side == .front
                            ? "Hold the front of the card inside the frame. It's captured when the number reads clearly."
                            : "Hold the back of the card inside the frame, with the signature strip in view."
                    )
                    .font(.headline)
                    ScannedCardSummary(card: camera.found, side: side)
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .frame(maxWidth: 560)
                HStack(spacing: 24) {
                    shutter
                    photoButton
                }
            }
            .padding()
        }
        .background(.black)
    }

    private var shutter: some View {
        Button {
            camera.shutter()
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 58, height: 58)
                Circle().stroke(.white, lineWidth: 4).frame(width: 70, height: 70)
                if camera.isCapturing { ProgressView().tint(.black) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.hasFrame || camera.isCapturing)
        .accessibilityLabel("Capture")
        .accessibilityHint("Takes the card as it is now, to check what was read.")
    }
}

#if os(iOS)
    /// What the camera sees, filling the view.
    private struct CameraPreview: UIViewRepresentable {
        let session: AVCaptureSession
        let rotation: CGFloat

        func makeUIView(context: Context) -> PreviewView {
            let view = PreviewView()
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            return view
        }

        func updateUIView(_ view: PreviewView, context: Context) {
            view.previewLayer.connection.map { CameraPreviewConnection.apply(rotation, to: $0) }
        }

        final class PreviewView: UIView {
            override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
            // The layer class above makes this cast safe.
            var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        }
    }
#else
    /// What the camera sees, filling the view.
    private struct CameraPreview: NSViewRepresentable {
        let session: AVCaptureSession
        let rotation: CGFloat

        func makeNSView(context: Context) -> PreviewView {
            let view = PreviewView(frame: .zero)
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            return view
        }

        func updateNSView(_ view: PreviewView, context: Context) {
            view.previewLayer.connection.map { CameraPreviewConnection.apply(rotation, to: $0) }
        }

        final class PreviewView: NSView {
            let previewLayer = AVCaptureVideoPreviewLayer()

            override init(frame: NSRect) {
                super.init(frame: frame)
                // A layer-hosting view: the preview layer is the view's own.
                layer = previewLayer
                wantsLayer = true
            }

            required init?(coder: NSCoder) { nil }
        }
    }
#endif

/// Keeps the preview level and unmirrored. A Mac's front camera is mirrored by default, which
/// would show the card's text backwards and put the boxes, read from unmirrored frames, on the
/// wrong side.
private enum CameraPreviewConnection {
    static func apply(_ rotation: CGFloat, to connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(rotation), connection.videoRotationAngle != rotation {
            connection.videoRotationAngle = rotation
        }
        if connection.isVideoMirroringSupported,
            connection.automaticallyAdjustsVideoMirroring || connection.isVideoMirrored
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }
}

/// The guide, the card's edge and the text read, over the preview. The preview fills the view
/// (aspect fill), so the frame is scaled the same way here.
private struct CardOverlay: View {
    let analysis: CardAnalysis

    var body: some View {
        GeometryReader { proxy in
            let view = proxy.size
            let frame = analysis.imageSize
            let scale = frame.width > 0 ? max(view.width / frame.width, view.height / frame.height) : 1
            let drawn = CGSize(width: frame.width * scale, height: frame.height * scale)
            ZStack {
                if let quad = analysis.quad {
                    Path { path in
                        let points = quad.points.map { CGPoint(x: $0.x * drawn.width, y: $0.y * drawn.height) }
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
                // Every line read, faintly until the card's edge is found; then only those on it.
                ForEach(analysis.lines) { line in
                    LineBox(line: line, size: drawn, neutral: .white)
                }
                .opacity(analysis.quad == nil ? 0.6 : 1)
            }
            .frame(width: drawn.width, height: drawn.height)
            .position(x: view.width / 2, y: view.height / 2)
            if analysis.quad == nil {
                let width = min(view.width - 48, 460)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .frame(width: width, height: width / 1.586)
                    .position(x: view.width / 2, y: view.height * 0.4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: analysis.quad)
    }
}

/// The back camera, read about three times a second while the scan is open. Everything stays in
/// memory and stops when the sheet closes.
@MainActor
@Observable
final class CardCamera {
    enum State: Equatable {
        case starting, running
        case unavailable(String)
    }

    /// A camera, for the menu.
    struct Choice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// A frame taken for the review, with its careful reading.
    struct Capture: Identifiable {
        let id = UUID()
        let image: CGImage
        let analysis: CardAnalysis
    }

    private(set) var state = State.starting
    /// The latest live reading, for the overlay.
    private(set) var live = CardAnalysis.empty
    /// Everything read so far, for the summary.
    private(set) var found = ScannedCard()
    private(set) var capture: Capture?
    private(set) var isCapturing = false
    private(set) var hasFrame = false
    private(set) var hasTorch = false
    private(set) var isTorchOn = false
    /// The cameras to choose from, best first, and the one in use.
    private(set) var cameras: [Choice] = []
    private(set) var cameraID: String?
    /// The angle that keeps the picture level, for the preview.
    private(set) var rotation: CGFloat = 90

    let side: CardScanSide
    let cardNumber: String?
    @ObservationIgnored private let pipeline = CapturePipeline()
    @ObservationIgnored private var lastFrame: CGImage?
    @ObservationIgnored private var lastKey: String?
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?

    init(side: CardScanSide, cardNumber: String?) {
        self.side = side
        self.cardNumber = cardNumber
    }

    /// The cameras that can read a card, best first: on iPhone and iPad the back camera; on a
    /// Mac a nearby iPhone (Continuity Camera), then a plugged-in camera, then the built-in one.
    nonisolated static func availableCameras() -> [AVCaptureDevice] {
        #if os(iOS)
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back).map { [$0] } ?? []
        #else
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.continuityCamera, .external, .builtInWideAngleCamera], mediaType: .video,
                position: .unspecified
            ).devices.sorted { rank($0.deviceType) < rank($1.deviceType) }
        #endif
    }

    nonisolated static var defaultCamera: AVCaptureDevice? { availableCameras().first }

    /// How well a kind of camera reads a card: an iPhone's back camera focuses close and sees
    /// fine print, a webcam less so.
    nonisolated static func rank(_ type: AVCaptureDevice.DeviceType) -> Int {
        switch type {
        case .continuityCamera: 0
        case .external: 1
        case .builtInWideAngleCamera: 2
        default: 3
        }
    }

    var session: AVCaptureSession { pipeline.session }

    func start() async {
        let denied = "Allow Silicon Wallet to use the camera in Settings ▸ Privacy & Security ▸ Camera."
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .unavailable(denied)
                return
            }
        default:
            state = .unavailable(denied)
            return
        }
        let available = Self.availableCameras()
        cameras = available.map { Choice(id: $0.uniqueID, name: $0.localizedName) }
        guard let device = available.first else {
            #if os(macOS)
                state = .unavailable(
                    "No camera was found. Take a photo with your iPhone or iPad instead, or connect a camera.")
            #else
                state = .unavailable("No camera was found.")
            #endif
            return
        }
        guard attach(device) else {
            state = .unavailable("The camera couldn't start. Close this and try again.")
            return
        }
        pipeline.onFrame = { [weak self] image in
            Task { @MainActor in await self?.read(image) }
        }
        pipeline.run()
        state = .running
    }

    /// Switches to another camera, starting the reading afresh.
    func select(cameraID id: String) {
        guard id != cameraID, capture == nil, let device = AVCaptureDevice(uniqueID: id) else { return }
        setTorch(false)
        live = .empty
        lastKey = nil
        lastFrame = nil
        hasFrame = false
        if !attach(device) {
            state = .unavailable("That camera couldn't start. Close this and try again.")
        }
    }

    /// A photo from elsewhere (Continuity Camera on a Mac), read and reviewed like a capture.
    func use(photo: CGImage) {
        Task { await take(photo) }
    }

    /// Reads from `device`, keeping the picture level as it turns.
    private func attach(_ device: AVCaptureDevice) -> Bool {
        guard pipeline.configure(device: device) else { return false }
        self.device = device
        cameraID = device.uniqueID
        hasTorch = device.hasTorch
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.coordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
            [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.applyRotation(angle) }
        }
        return true
    }

    func stop() {
        pipeline.onFrame = nil
        setTorch(false)
        pipeline.halt()
        rotationObservation = nil
        coordinator = nil
        device = nil
        lastFrame = nil
        capture = nil
        live = .empty
    }

    func shutter() {
        guard let lastFrame else { return }
        Task { await take(lastFrame) }
    }

    func retake() {
        capture = nil
        found = ScannedCard()
        live = .empty
        lastKey = nil
        lastFrame = nil
        hasFrame = false
        pipeline.run()
    }

    func toggleTorch() { setTorch(!isTorchOn) }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        isTorchOn = on
    }

    private func applyRotation(_ angle: CGFloat) {
        rotation = angle
        pipeline.setRotation(angle)
    }

    /// Reads one live frame, and captures it once the same number or code has read twice with
    /// the card's edge in view.
    private func read(_ image: CGImage) async {
        defer { pipeline.ready() }
        guard capture == nil, !isCapturing,
            let analysis = try? await CardImageAnalyzer.analyse(
                image, side: side, cardNumber: cardNumber, detail: .live),
            capture == nil, !isCapturing
        else { return }
        live = analysis
        lastFrame = image
        hasFrame = true
        if analysis.quad != nil { found = found.merged(with: analysis.card) }
        let key = analysis.quad == nil ? nil : side == .front ? analysis.card.number : analysis.card.securityCode
        if let key, key == lastKey {
            await take(image)
        }
        lastKey = key
    }

    private func take(_ image: CGImage) async {
        guard !isCapturing, capture == nil else { return }
        isCapturing = true
        setTorch(false)
        pipeline.halt()
        var careful =
            (try? await CardImageAnalyzer.analyse(image, side: side, cardNumber: cardNumber, detail: .still)) ?? live
        // The careful reading first; what the live frames read fills its gaps.
        careful.card = careful.card.merged(with: found)
        capture = Capture(image: careful.image ?? image, analysis: careful)
        isCapturing = false
    }
}

/// The capture session and its frames, worked on a queue of their own. Frames are handed on
/// one at a time, at most about three a second, and dropped while one is being read.
private final class CapturePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "SiliconWallet.CardCamera")
    private let lock = NSLock()
    private var busy = false
    private var lastFrame = Date.distantPast
    private var handler: (@Sendable (CGImage) -> Void)?
    private let context = CIContext(options: [.cacheIntermediates: false])

    var onFrame: (@Sendable (CGImage) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    func configure(device: AVCaptureDevice) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // A different camera replaces the one before.
        for old in session.inputs { session.removeInput(old) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        // Mac cameras vary; take 1080p where there is one.
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { return false }
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            #if os(iOS)
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            #endif
            device.unlockForConfiguration()
        }
        return true
    }

    func setRotation(_ angle: CGFloat) {
        queue.async { [self] in
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func run() {
        ready()
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func halt() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// The last frame handed on has been read; the next may follow.
    func ready() { lock.withLock { busy = false } }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let next: (@Sendable (CGImage) -> Void)? = lock.withLock {
            guard !busy, Date().timeIntervalSince(lastFrame) > 0.3, let handler = self.handler else { return nil }
            busy = true
            lastFrame = Date()
            return handler
        }
        guard let next else { return }
        guard let buffer = sampleBuffer.imageBuffer else {
            ready()
            return
        }
        let frame = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(frame, from: frame.extent) else {
            ready()
            return
        }
        next(image)
    }
}

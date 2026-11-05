import AVFoundation
import CoreImage
import SiliconWalletKit
import SwiftUI

/// Scans a card live with the camera, on this device (ADR-0009). A card-shaped guide shows where
/// to hold it; once its edge is found, the edge and the text read are drawn over it, and the
/// frame is captured by itself when the same number (or, on the back, code) reads twice. The
/// shutter captures by hand. The capture opens the review, to check and correct before Use.
/// Frames and the capture are only ever in memory.
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

    static var isSupported: Bool { CardCamera.backCamera != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let capture = camera.capture {
                    ScrollView {
                        CardScanReview(image: capture.image, side: side, lines: $lines, card: $card)
                            .padding()
                    }
                } else if case .unavailable(let message) = camera.state {
                    ContentUnavailableView("Camera Unavailable", systemImage: "camera", description: Text(message))
                } else {
                    live
                }
            }
            .navigationTitle(side == .front ? "Scan Card" : "Scan Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    ToolbarItem(placement: .bottomBar) {
                        Button("Retake", systemImage: "arrow.counterclockwise") { camera.retake() }
                            .labelStyle(.titleAndIcon)
                    }
                } else if camera.hasTorch {
                    ToolbarItem(placement: .primaryAction) {
                        Button(
                            camera.isTorchOn ? "Turn Torch Off" : "Turn Torch On",
                            systemImage: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                        ) { camera.toggleTorch() }
                    }
                }
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capture?.id) {
            lines = camera.capture?.analysis.lines ?? []
            card = camera.capture?.analysis.card ?? ScannedCard()
        }
        .sensoryFeedback(.success, trigger: camera.capture?.id) { _, new in new != nil }
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
            .padding()
        }
        .background(.black)
    }
}

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
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(rotation),
            connection.videoRotationAngle != rotation
        {
            connection.videoRotationAngle = rotation
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // The layer class above makes this cast safe.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
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
                    ForEach(analysis.lines) { line in
                        LineBox(line: line, size: drawn)
                    }
                }
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
    /// The angle that keeps the picture level, for the preview.
    private(set) var rotation: CGFloat = 90

    let side: CardScanSide
    let cardNumber: String?
    @ObservationIgnored private let pipeline = CapturePipeline()
    @ObservationIgnored private var lastFrame: CGImage?
    @ObservationIgnored private var lastKey: String?
    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?

    init(side: CardScanSide, cardNumber: String?) {
        self.side = side
        self.cardNumber = cardNumber
    }

    nonisolated static var backCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
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
        guard let device = Self.backCamera, pipeline.configure(device: device) else {
            state = .unavailable("The camera couldn't start. Close this and try again.")
            return
        }
        hasTorch = device.hasTorch
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.coordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
            [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.applyRotation(angle) }
        }
        pipeline.onFrame = { [weak self] image in
            Task { @MainActor in await self?.read(image) }
        }
        pipeline.run()
        state = .running
    }

    func stop() {
        pipeline.onFrame = nil
        setTorch(false)
        pipeline.halt()
        rotationObservation = nil
        coordinator = nil
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
        guard let device = Self.backCamera, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
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
        session.sessionPreset = .hd1920x1080
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
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

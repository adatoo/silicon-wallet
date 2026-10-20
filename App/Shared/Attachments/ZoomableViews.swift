import PDFKit
import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// A preview that can zoom: an image's scroll view or a PDF view.
@MainActor
protocol ZoomTarget: AnyObject {
    func zoom(by factor: CGFloat)
    func zoomToFit()
    func zoomToActualSize()
}

/// Connects the preview's zoom buttons to its image or PDF view, and tells the buttons when they
/// would do nothing.
@MainActor
@Observable
final class ZoomController {
    private(set) var canZoomIn = false
    private(set) var canZoomOut = false
    private(set) var isFitting = true
    private(set) var isActualSize = false
    @ObservationIgnored weak var target: (any ZoomTarget)?

    func zoomIn() { target?.zoom(by: PreviewGeometry.zoomStep) }
    func zoomOut() { target?.zoom(by: 1 / PreviewGeometry.zoomStep) }
    func zoomToFit() { target?.zoomToFit() }
    func actualSize() { target?.zoomToActualSize() }

    /// Called by the target whenever its scale may have changed. Only real changes are stored,
    /// so a layout pass doesn't redraw the toolbar.
    func update(scale: CGFloat, minimum: CGFloat, maximum: CGFloat, isFitting fitting: Bool) {
        let tolerance: CGFloat = 0.001
        let canIn = scale < maximum - tolerance
        let canOut = scale > minimum + tolerance
        let actual = abs(scale - 1) < tolerance
        if canZoomIn != canIn { canZoomIn = canIn }
        if canZoomOut != canOut { canZoomOut = canOut }
        if isFitting != fitting { isFitting = fitting }
        if isActualSize != actual { isActualSize = actual }
    }
}

private func approximatelyEqual(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

#if os(macOS)
    /// An image that fits its space until you zoom: pinch, double-click, scroll to pan, or the
    /// controller's buttons. Resizing the window refits it while it's fitted.
    struct ZoomableImage: NSViewRepresentable {
        let image: NSImage
        let controller: ZoomController

        func makeNSView(context: Context) -> ZoomingImageScrollView {
            let view = ZoomingImageScrollView(image: image)
            view.controller = controller
            controller.target = view
            return view
        }

        func updateNSView(_ view: ZoomingImageScrollView, context: Context) {}
    }

    final class ZoomingImageScrollView: NSScrollView, ZoomTarget {
        weak var controller: ZoomController?
        private let imageSize: CGSize
        private var isFitting = true

        init(image: NSImage) {
            imageSize = image.size
            super.init(frame: .zero)
            let clip = CenteringClipView()
            clip.drawsBackground = false
            contentView = clip
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageFrameStyle = .none
            // Copying would put the decrypted image on the clipboard.
            imageView.allowsCutCopyPaste = false
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            documentView = imageView
            allowsMagnification = true
            maxMagnification = PreviewGeometry.maximumScale
            hasHorizontalScroller = true
            hasVerticalScroller = true
            autohidesScrollers = true
            drawsBackground = false
            borderType = .noBorder
            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(doubleClicked(_:)))
            doubleClick.numberOfClicksRequired = 2
            addGestureRecognizer(doubleClick)
            NotificationCenter.default.addObserver(
                self, selector: #selector(liveMagnifyEnded), name: NSScrollView.didEndLiveMagnifyNotification,
                object: self)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        private var fitScale: CGFloat {
            PreviewGeometry.fitScale(content: imageSize, in: contentView.frame.size)
        }

        /// The middle of what's showing, in the image's coordinates.
        private var visibleCentre: NSPoint {
            NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        }

        override func layout() {
            super.layout()
            let fit = fitScale
            if !approximatelyEqual(minMagnification, fit) { minMagnification = fit }
            if isFitting || magnification < fit {
                isFitting = true
                if !approximatelyEqual(magnification, fit) { magnification = fit }
            }
            report()
        }

        func zoom(by factor: CGFloat) {
            let scale = min(maxMagnification, max(minMagnification, magnification * factor))
            isFitting = approximatelyEqual(scale, fitScale)
            setMagnification(scale, centeredAt: visibleCentre)
            report(scale)
        }

        func zoomToFit() {
            isFitting = true
            magnification = fitScale
            report(fitScale)
        }

        func zoomToActualSize() {
            let scale = max(1, minMagnification)
            isFitting = approximatelyEqual(scale, fitScale)
            setMagnification(scale, centeredAt: visibleCentre)
            report(scale)
        }

        @objc private func doubleClicked(_ recognizer: NSClickGestureRecognizer) {
            let fit = fitScale
            guard magnification <= fit + 0.0001, let documentView else { return zoomToFit() }
            let scale = PreviewGeometry.doubleTapScale(fit: fit)
            isFitting = approximatelyEqual(scale, fit)
            let point = documentView.convert(recognizer.location(in: self), from: self)
            setMagnification(scale, centeredAt: point)
            report(scale)
        }

        @objc private func liveMagnifyEnded() {
            isFitting = approximatelyEqual(magnification, fitScale)
            report()
        }

        private func report(_ scale: CGFloat? = nil) {
            controller?.update(
                scale: scale ?? magnification, minimum: minMagnification, maximum: maxMagnification,
                isFitting: isFitting)
        }
    }

    /// Keeps a document smaller than the view in the middle, rather than in a corner.
    final class CenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var rect = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return rect }
            let document = documentView.frame
            if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
            if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
            return rect
        }
    }

    struct PDFPreview: NSViewRepresentable {
        let document: PDFDocument
        let controller: ZoomController

        func makeNSView(context: Context) -> ZoomablePDFView {
            ZoomablePDFView(document: document, controller: controller)
        }

        func updateNSView(_ view: ZoomablePDFView, context: Context) {}
    }
#else
    /// An image that fits its space until you zoom: pinch, double-tap, drag to pan, or the
    /// controller's buttons. Rotating or resizing refits it while it's fitted.
    struct ZoomableImage: UIViewRepresentable {
        let image: UIImage
        let controller: ZoomController

        func makeUIView(context: Context) -> ZoomingImageScrollView {
            let view = ZoomingImageScrollView(image: image)
            view.controller = controller
            controller.target = view
            return view
        }

        func updateUIView(_ view: ZoomingImageScrollView, context: Context) {}
    }

    final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate, ZoomTarget {
        weak var controller: ZoomController?
        private let imageView: UIImageView
        private var isFitting = true

        init(image: UIImage) {
            imageView = UIImageView(image: image)
            super.init(frame: .zero)
            imageView.frame = CGRect(origin: .zero, size: image.size)
            addSubview(imageView)
            contentSize = image.size
            delegate = self
            maximumZoomScale = PreviewGeometry.maximumScale
            contentInsetAdjustmentBehavior = .never
            bouncesZoom = true
            decelerationRate = .fast
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        private var fitScale: CGFloat {
            PreviewGeometry.fitScale(content: imageView.image?.size ?? .zero, in: bounds.size)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let fit = fitScale
            if !approximatelyEqual(minimumZoomScale, fit) { minimumZoomScale = fit }
            if isFitting || zoomScale < fit {
                isFitting = true
                if !approximatelyEqual(zoomScale, fit) { zoomScale = fit }
            }
            centre()
            report()
        }

        /// Insets a zoomed-out image so it sits in the middle.
        private func centre() {
            let size = imageView.frame.size
            let x = max(0, (bounds.width - size.width) / 2)
            let y = max(0, (bounds.height - size.height) / 2)
            let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
            if contentInset != inset { contentInset = inset }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isFitting = false
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centre()
            report()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isFitting = approximatelyEqual(scale, fitScale)
            report()
        }

        func zoom(by factor: CGFloat) {
            let scale = min(maximumZoomScale, max(minimumZoomScale, zoomScale * factor))
            isFitting = approximatelyEqual(scale, fitScale)
            setZoomScale(scale, animated: true)
            report(scale)
        }

        func zoomToFit() {
            isFitting = true
            setZoomScale(fitScale, animated: true)
            report(fitScale)
        }

        func zoomToActualSize() {
            let scale = max(1, minimumZoomScale)
            isFitting = approximatelyEqual(scale, fitScale)
            setZoomScale(scale, animated: true)
            report(scale)
        }

        @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            let fit = fitScale
            guard zoomScale <= fit + 0.0001 else { return zoomToFit() }
            let scale = PreviewGeometry.doubleTapScale(fit: fit)
            isFitting = approximatelyEqual(scale, fit)
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(
                to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
                animated: true)
            report(scale)
        }

        private func report(_ scale: CGFloat? = nil) {
            controller?.update(
                scale: scale ?? zoomScale, minimum: minimumZoomScale, maximum: maximumZoomScale, isFitting: isFitting)
        }
    }

    struct PDFPreview: UIViewRepresentable {
        let document: PDFDocument
        let controller: ZoomController

        func makeUIView(context: Context) -> ZoomablePDFView {
            ZoomablePDFView(document: document, controller: controller)
        }

        func updateUIView(_ view: ZoomablePDFView, context: Context) {}
    }
#endif

/// A PDF that fits its space until you zoom, with PDFKit's own pinch and scrolling.
final class ZoomablePDFView: PDFView, ZoomTarget {
    private weak var controller: ZoomController?

    init(document: PDFDocument, controller: ZoomController) {
        self.controller = controller
        super.init(frame: .zero)
        autoScales = true
        self.document = document
        controller.target = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: self)
        report()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func zoom(by factor: CGFloat) {
        if factor > 1 { zoomIn(nil) } else { zoomOut(nil) }
    }

    func zoomToFit() {
        autoScales = true
        report()
    }

    func zoomToActualSize() {
        autoScales = false
        scaleFactor = 1
        report()
    }

    @objc private func scaleChanged() { report() }

    private func report() {
        controller?.update(scale: scaleFactor, minimum: minScaleFactor, maximum: maxScaleFactor, isFitting: autoScales)
    }
}

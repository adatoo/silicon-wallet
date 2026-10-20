import CoreGraphics

/// Sizes and zoom levels for attachment previews.
enum PreviewGeometry {
    /// Each Zoom In or Zoom Out multiplies or divides the scale by this.
    static let zoomStep: CGFloat = 1.5
    static let maximumScale: CGFloat = 8

    /// The scale that shows all of `content` in `bounds`, never above actual size, so a small
    /// image isn't blown up.
    static func fitScale(content: CGSize, in bounds: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(1, bounds.width / content.width, bounds.height / content.height)
    }

    /// The size to open a preview at: the whole content, scaled down to fit `available`, but at
    /// least `minimum`.
    static func idealSize(content: CGSize, available: CGSize, minimum: CGSize) -> CGSize {
        let scale = fitScale(content: content, in: available)
        return CGSize(
            width: max(minimum.width, (content.width * scale).rounded()),
            height: max(minimum.height, (content.height * scale).rounded()))
    }

    /// Where a double-click or double-tap zooms to from the fitted scale.
    static func doubleTapScale(fit: CGFloat) -> CGFloat {
        min(maximumScale, fit * 2.5)
    }
}

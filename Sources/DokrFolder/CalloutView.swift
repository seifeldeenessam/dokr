import AppKit

/// The popup's backdrop, shaped like a Dock stack: a rounded bubble with a tail pointing at the
/// Dock tile. Blurred material clipped to the shape, plus a thin light rim.
final class CalloutView: NSView {
    static let cornerRadius: CGFloat = 26
    static let tailLength: CGFloat = 12
    static let tailHalfWidth: CGFloat = 14

    /// Keeps the tail out of the rounded corners.
    static var tailMargin: CGFloat { cornerRadius + tailHalfWidth }

    /// Insets for the content so it sits in the bubble, not the tail.
    static func contentInsets(for edge: DockSettings.Edge) -> NSEdgeInsets {
        switch edge {
        case .bottom: return NSEdgeInsets(top: 0, left: 0, bottom: tailLength, right: 0)
        case .left: return NSEdgeInsets(top: 0, left: tailLength, bottom: 0, right: 0)
        case .right: return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: tailLength)
        }
    }

    private let path: CGPath

    /// `tailPosition`: distance along the Dock-facing edge (x for bottom, y for left/right).
    init(frame: NSRect, edge: DockSettings.Edge, tailPosition: CGFloat, content: NSView) {
        path = Self.path(size: frame.size, edge: edge, tailPosition: tailPosition)
        super.init(frame: frame)

        let material = NSVisualEffectView(frame: bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.mask(path: path, size: frame.size)
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        let insets = Self.contentInsets(for: edge)
        content.frame = NSRect(
            x: insets.left,
            y: insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )
        addSubview(content)

        let rim = RimView(frame: bounds, path: path)
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func mask(path: CGPath, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }

    /// Built for a tail on the bottom edge, then flipped/rotated onto the Dock's edge.
    static func path(size: NSSize, edge: DockSettings.Edge, tailPosition p: CGFloat) -> CGPath {
        let vertical = edge != .bottom
        let w = vertical ? size.height : size.width
        let h = vertical ? size.width : size.height
        let l = tailLength
        let t = tailHalfWidth
        let r = min(cornerRadius, (h - l) / 2, w / 2)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: p + t, y: l))
        path.addArc(tangent1End: CGPoint(x: w, y: l), tangent2End: CGPoint(x: w, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: 0, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: l), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: l), tangent2End: CGPoint(x: w, y: l), radius: r)
        path.addLine(to: CGPoint(x: p - t, y: l))
        // Soft shoulders and a slightly rounded tip, like the Dock's.
        path.addCurve(
            to: CGPoint(x: p, y: 0),
            control1: CGPoint(x: p - t * 0.45, y: l),
            control2: CGPoint(x: p - 2.5, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: p + t, y: l),
            control1: CGPoint(x: p + 2.5, y: 0),
            control2: CGPoint(x: p + t * 0.45, y: l)
        )
        path.closeSubpath()

        var transform: CGAffineTransform
        switch edge {
        case .bottom: transform = .identity
        // (x, y) -> (y, x): tail on the left edge.
        case .left: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        // (x, y) -> (width - y, x): tail on the right edge.
        case .right: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        }
        return path.copy(using: &transform) ?? path
    }
}

private final class RimView: NSView {
    private let path: CGPath

    init(frame: NSRect, path: CGPath) {
        self.path = path
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Decoration only; clicks go to the grid underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Clip to the shape so only the inner half of the stroke shows: a crisp hairline.
        context.addPath(path)
        context.clip()
        context.addPath(path)
        context.setLineWidth(1.5)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.strokePath()
    }
}

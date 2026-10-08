import AppKit
import DokrCore

/// Draws the iOS-style folder icon: a rounded plate with a 3×3 grid of app icons.
public enum FolderIconRenderer {
    public enum Style {
        /// We draw the plate ourselves (macOS 13–15).
        case plate
        /// Just the grid. macOS 26+ puts any icon that isn't its own squircle on a system
        /// plate, so drawing ours too would nest one inside the other.
        case gridOnly
    }

    /// The style generated folder apps should use on this macOS version.
    public static var dockStyle: Style {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) ? .gridOnly : .plate
    }

    /// Lazily drawn image for previews in the editor (always with a plate, which is
    /// what the Dock ends up showing on every version).
    public static func image(for folder: AppFolder, size: CGFloat) -> NSImage {
        let icons = folder.apps.prefix(9).map(\.icon)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(icons: icons, in: rect, style: .plate)
            return true
        }
    }

    /// `.icns` data for the generated folder app.
    public static func icns(for folder: AppFolder, style: Style = dockStyle) -> Data {
        let icons = folder.apps.prefix(9).map(\.icon)
        var rendered: [Int: Data] = [:]
        let images: [(type: String, png: Data)] = ICNS.entries.compactMap { entry -> (type: String, png: Data)? in
            if rendered[entry.pixels] == nil {
                rendered[entry.pixels] = png(icons: icons, pixels: entry.pixels, style: style)
            }
            return rendered[entry.pixels].map { (entry.type, $0) }
        }
        return ICNS.encode(images)
    }

    static func png(icons: [NSImage], pixels: Int, style: Style) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(icons: icons, in: NSRect(x: 0, y: 0, width: pixels, height: pixels), style: style)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func draw(icons: [NSImage], in canvas: NSRect, style: Style) {
        let s = canvas.width
        let grid: NSRect

        switch style {
        case .plate:
            // macOS icon grid: 824pt body on a 1024pt canvas.
            let body = canvas.insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
            drawPlate(body, canvasSize: s)
            grid = body.insetBy(dx: body.width * 0.11, dy: body.width * 0.11)
        case .gridOnly:
            // The system shrinks the whole canvas onto its plate, so use nearly all of it.
            grid = canvas.insetBy(dx: s * 0.06, dy: s * 0.06)
        }

        let gap = grid.width * 0.04
        let cell = (grid.width - gap * 2) / 3
        for (index, icon) in icons.prefix(9).enumerated() {
            let row = CGFloat(index / 3)
            let col = CGFloat(index % 3)
            let rect = NSRect(
                x: grid.minX + col * (cell + gap),
                y: grid.maxY - (row + 1) * cell - row * gap,
                width: cell,
                height: cell
            )
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private static func drawPlate(_ body: NSRect, canvasSize s: CGFloat) {
        let radius = body.width * 0.225
        let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = s * 12 / 1024
        shadow.shadowOffset = NSSize(width: 0, height: -s * 8 / 1024)
        shadow.set()
        NSGradient(
            starting: NSColor(white: 0.96, alpha: 0.97),
            ending: NSColor(white: 0.80, alpha: 0.97)
        )?.draw(in: shape, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.7).setStroke()
        shape.lineWidth = max(0.5, s / 512)
        shape.stroke()
    }
}

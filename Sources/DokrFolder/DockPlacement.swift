import AppKit

/// The Dock settings that matter for placing the popup, read from `com.apple.dock`.
struct DockSettings: CustomStringConvertible {
    enum Edge: String {
        case bottom, left, right
    }

    var edge: Edge = .bottom
    var autohide = false
    var tileSize: CGFloat = 48
    var magnification = false
    var largeSize: CGFloat = 128
    /// System Settings → Desktop & Dock → "Show indicators for open applications".
    var showsIndicators = true

    static func current() -> DockSettings {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        func value<T>(_ key: String) -> T? {
            CFPreferencesCopyAppValue(key as CFString, domain) as? T
        }

        var settings = DockSettings()
        if let orientation: String = value("orientation"), let edge = Edge(rawValue: orientation) {
            settings.edge = edge
        }
        if let autohide: Bool = value("autohide") { settings.autohide = autohide }
        if let tileSize: Double = value("tilesize") { settings.tileSize = tileSize }
        if let magnification: Bool = value("magnification") { settings.magnification = magnification }
        if let largeSize: Double = value("largesize") { settings.largeSize = largeSize }
        if let indicators: Bool = value("show-process-indicators") { settings.showsIndicators = indicators }
        return settings
    }

    /// How far the Dock reaches into the screen while the pointer is on it
    /// (icons + padding, magnified icons included).
    var reach: CGFloat {
        (magnification ? max(tileSize, largeSize) : tileSize) + 18
    }

    var description: String {
        "edge=\(edge.rawValue) autohide=\(autohide) tile=\(Int(tileSize)) magnify=\(magnification ? Int(largeSize) : 0)"
    }
}

/// Places the popup next to the Dock tile that was just clicked (the pointer is on it).
/// `size` includes the callout's tail, whose tip ends up `dockGap` from the Dock.
enum PopupPlacement {
    static let gap: CGFloat = 10
    static let dockGap: CGFloat = 4

    static func frame(for size: NSSize, near mouse: NSPoint, dock: DockSettings) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let full = screen.frame
        let visible = screen.visibleFrame

        // With the Dock pinned, visibleFrame already excludes it. With auto-hide it doesn't,
        // so fall back to the Dock's reach (it's slid in right now, the pointer is on it).
        var origin: NSPoint
        switch dock.edge {
        case .bottom:
            let inset = max(visible.minY - full.minY, dock.reach)
            origin = NSPoint(x: mouse.x - size.width / 2, y: full.minY + inset + dockGap)
        case .left:
            let inset = max(visible.minX - full.minX, dock.reach)
            origin = NSPoint(x: full.minX + inset + dockGap, y: mouse.y - size.height / 2)
        case .right:
            let inset = max(full.maxX - visible.maxX, dock.reach)
            origin = NSPoint(x: full.maxX - inset - dockGap - size.width, y: mouse.y - size.height / 2)
        }

        // Keep it on screen and below the menu bar; only slide along the Dock's axis.
        let top = visible.maxY - gap
        switch dock.edge {
        case .bottom:
            origin.x = clamp(origin.x, full.minX + gap, full.maxX - size.width - gap)
            origin.y = min(origin.y, top - size.height)
        case .left, .right:
            origin.y = clamp(origin.y, full.minY + gap, top - size.height)
        }
        return NSRect(origin: origin, size: size)
    }

    /// Where the tail sits along the popup's Dock-facing edge: under the pointer, kept clear
    /// of the rounded corners when the popup had to slide to stay on screen.
    static func tailPosition(in frame: NSRect, mouse: NSPoint, dock: DockSettings, margin: CGFloat) -> CGFloat {
        switch dock.edge {
        case .bottom: return clamp(mouse.x - frame.minX, margin, frame.width - margin)
        case .left, .right: return clamp(mouse.y - frame.minY, margin, frame.height - margin)
        }
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

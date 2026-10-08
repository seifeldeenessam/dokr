import AppKit
import DokrCore

public extension AppEntry {
    /// Builds an entry from an `.app` bundle URL.
    init?(appURL url: URL) {
        guard url.pathExtension == "app" else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        self.init(
            name: name,
            path: url.standardizedFileURL.path,
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier
        )
    }

    /// The app's current location: the saved path, or wherever its bundle ID lives now.
    var resolvedURL: URL? {
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        return nil
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: resolvedURL?.path ?? path)
    }
}

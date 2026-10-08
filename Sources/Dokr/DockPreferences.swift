import DokrCore
import Foundation

enum DockPreferencesError: LocalizedError {
    case syncFailed

    var errorDescription: String? {
        "Couldn't save the Dock preferences (com.apple.dock)."
    }
}

/// Reads/writes `com.apple.dock` arrays via CFPreferences.
/// Requires a non-sandboxed app: a sandboxed app can't write another app's domain.
struct DockPreferences {
    private let domain = DockAppsCodec.domain as CFString

    func tiles(for key: String) -> [DockAppsCodec.Tile] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain) as? [DockAppsCodec.Tile] ?? []
    }

    func setTiles(_ tiles: [DockAppsCodec.Tile], for key: String) throws {
        try backup(self.tiles(for: key), key: key)
        CFPreferencesSetAppValue(key as CFString, tiles as NSArray, domain)
        guard CFPreferencesAppSynchronize(domain) else { throw DockPreferencesError.syncFailed }
    }

    /// The Dock only re-reads its preferences on launch; launchd relaunches it immediately.
    func restartDock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try process.run()
        process.waitUntilExit()
    }

    /// Keeps the last 10 snapshots in ~/Library/Application Support/Dokr/Backups (see README to restore).
    private func backup(_ tiles: [DockAppsCodec.Tile], key: String) throws {
        let fm = FileManager.default
        let dir = FolderStore.supportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let data = try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("\(key)-\(stamp).plist"), options: .atomic)

        let old = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(key) && $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(10)
        for url in old { try? fm.removeItem(at: url) }
    }
}

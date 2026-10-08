import Foundation

/// Edits the Dock's `com.apple.dock` → `persistent-apps` array (the app side of the Dock).
///
/// An app tile looks like:
///
///     {
///       "GUID": 1234,
///       "tile-type": "file-tile",
///       "tile-data": {
///         "bundle-identifier": "com.apple.Safari",
///         "file-label": "Safari",
///         "file-type": 41,
///         "file-data": { "_CFURLString": "file:///Applications/Safari.app/", "_CFURLStringType": 15 },
///         ...
///       }
///     }
public enum DockAppsCodec {
    public static let domain = "com.apple.dock"
    public static let persistentAppsKey = "persistent-apps"

    public typealias Tile = [String: Any]

    /// A Dock tile Dokr owns (a generated folder app).
    public struct Item: Equatable, Sendable {
        public var path: String
        public var label: String
        public var bundleIdentifier: String

        public init(path: String, label: String, bundleIdentifier: String) {
            self.path = DockAppsCodec.normalize(path)
            self.label = label
            self.bundleIdentifier = bundleIdentifier
        }
    }

    // MARK: Read

    public static func path(of tile: Tile) -> String? {
        guard let data = tile["tile-data"] as? Tile,
              let fileData = data["file-data"] as? Tile,
              let string = fileData["_CFURLString"] as? String
        else { return nil }
        // _CFURLStringType: 0 = POSIX path, 15 = URL string.
        if (fileData["_CFURLStringType"] as? Int) == 0 {
            return normalize(string)
        }
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return normalize(url.path)
    }

    public static func bundleIdentifier(of tile: Tile) -> String? {
        (tile["tile-data"] as? Tile)?["bundle-identifier"] as? String
    }

    // MARK: Write

    public static func tile(for item: Item) -> Tile {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": item.bundleIdentifier,
                "file-label": item.label,
                "file-type": 41,
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: item.path, isDirectory: true).absoluteString,
                    "_CFURLStringType": 15,
                ] as Tile,
            ] as Tile,
        ]
    }

    /// Makes the Dock contain exactly `items` among the tiles under `managedDirectory`:
    /// existing ones keep their position (and GUID etc.), stale ones are dropped, new ones are
    /// appended. Tiles for `hiding` apps are removed (they now live inside a folder).
    /// All other tiles are left untouched.
    public static func sync(
        _ tiles: [Tile],
        items: [Item],
        managedDirectory: String,
        hiding hidden: [AppEntry] = []
    ) -> [Tile] {
        let managedPrefix = normalize(managedDirectory) + "/"
        let hiddenIDs = Set(hidden.compactMap(\.bundleIdentifier))
        let hiddenPaths = Set(hidden.map { normalize($0.path) })

        var pending = items
        var result: [Tile] = []

        for tile in tiles {
            guard let path = path(of: tile) else {
                result.append(tile)
                continue
            }
            if path.hasPrefix(managedPrefix) {
                guard let index = pending.firstIndex(where: { $0.path == path }) else { continue }
                let item = pending.remove(at: index)
                var updated = tile
                var data = updated["tile-data"] as? Tile ?? [:]
                data["file-label"] = item.label
                data["bundle-identifier"] = item.bundleIdentifier
                updated["tile-data"] = data
                result.append(updated)
            } else if hiddenPaths.contains(path) || bundleIdentifier(of: tile).map({ hiddenIDs.contains($0) }) == true {
                continue
            } else {
                result.append(tile)
            }
        }

        result += pending.map(tile(for:))
        return result
    }

    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

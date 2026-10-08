import Foundation

/// An app inside a folder. `path` is preferred; `bundleIdentifier` is the fallback if the app moves.
public struct AppEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier ?? path }

    public var name: String
    public var path: String
    public var bundleIdentifier: String?

    public init(name: String, path: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
    }
}

/// An iOS-style folder of apps that lives in the Dock as its own generated `.app`.
public struct AppFolder: Codable, Hashable, Identifiable, Sendable {
    public static let bundleIdentifierPrefix = "com.seifeldeenessam.dokr.folder."

    public var id: UUID
    public var name: String
    public var apps: [AppEntry]
    public var showInDock: Bool

    public init(id: UUID = UUID(), name: String, apps: [AppEntry] = [], showInDock: Bool = true) {
        self.id = id
        self.name = name
        self.apps = apps
        self.showInDock = showInDock
    }

    /// Stable per folder, so renames don't create a "new" app for the Dock / LaunchServices.
    public var bundleIdentifier: String {
        Self.bundleIdentifierPrefix + id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Unique, filesystem-safe bundle names (without `.app`) for each folder.
    public static func bundleNames(for folders: [AppFolder]) -> [UUID: String] {
        var used = Set<String>()
        var result: [UUID: String] = [:]
        for folder in folders {
            let base = sanitizedName(folder.name)
            var name = base
            var n = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(n)"
                n += 1
            }
            used.insert(name.lowercased())
            result[folder.id] = name
        }
        return result
    }

    static func sanitizedName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = String(cleaned.drop(while: { $0 == "." }))
        return visible.isEmpty ? "Folder" : visible
    }
}

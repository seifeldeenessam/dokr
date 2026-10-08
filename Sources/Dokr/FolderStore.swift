import DokrCore
import Foundation

/// Persists folder definitions to ~/Library/Application Support/Dokr/folders.json.
struct FolderStore {
    static let supportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dokr", isDirectory: true)

    /// Where the generated folder apps live (and what the Dock points at).
    static let foldersDirectory = supportDirectory.appendingPathComponent("Folders", isDirectory: true)

    private let fileURL = supportDirectory.appendingPathComponent("folders.json")

    func load() -> [AppFolder] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([AppFolder].self, from: data)) ?? []
    }

    func save(_ folders: [AppFolder]) throws {
        try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(folders).write(to: fileURL, options: .atomic)
    }
}

import DokrCore
import DokrKit
import Foundation

enum InstalledApps {
    /// Apps in the standard locations (one level of subfolders deep), sorted by name.
    static func scan() -> [AppEntry] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var seen = Set<String>()
        var result: [AppEntry] = []

        func visit(_ directory: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for url in items {
                if url.pathExtension == "app" {
                    if let entry = AppEntry(appURL: url), seen.insert(entry.id).inserted {
                        result.append(entry)
                    }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(url, depth: depth - 1)
                }
            }
        }

        for root in roots {
            visit(root, depth: 1)
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

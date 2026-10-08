import AppKit
import CoreServices
import DokrCore
import DokrKit

enum FolderBundleBuilderError: LocalizedError {
    case helperMissing(String)
    case codesignFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing(let path):
            return "The folder helper is missing at \(path). Rebuild Dokr with scripts/bundle.sh."
        case .codesignFailed(let output):
            return "Signing a folder app failed:\n\(output)"
        }
    }
}

/// Generates one small `.app` per folder:
///
///     <Name>.app/Contents/
///       Info.plist            unique bundle ID, LSUIElement, DokrResident
///       MacOS/DokrFolder      copy of the helper binary
///       Resources/AppIcon.icns  rendered 3×3 app grid
///       Resources/folder.json   the folder definition
struct FolderBundleBuilder {
    var directory = FolderStore.foldersDirectory
    var helperExecutable = Bundle.main.executableURL!
        .deletingLastPathComponent()
        .appendingPathComponent("DokrFolder")

    /// Builds bundles for `folders`, deletes stale ones, returns each folder's bundle URL.
    /// `resident`: the helper stays running to show the Dock's "open" dot (see DokrFolder).
    func build(_ folders: [AppFolder], resident: Bool) throws -> [UUID: URL] {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helperExecutable.path) else {
            throw FolderBundleBuilderError.helperMissing(helperExecutable.path)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let names = AppFolder.bundleNames(for: folders)
        var result: [UUID: URL] = [:]
        for folder in folders {
            let url = directory.appendingPathComponent("\(names[folder.id]!).app", isDirectory: true)
            try buildBundle(for: folder, at: url, resident: resident)
            result[folder.id] = url
        }

        let keep = Set(result.values.map(\.standardizedFileURL.path))
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == "app" && !keep.contains(url.standardizedFileURL.path) {
            try? fm.removeItem(at: url)
        }
        return result
    }

    private func buildBundle(for folder: AppFolder, at url: URL, resident: Bool) throws {
        let fm = FileManager.default
        // Build next to the target, then swap, so the Dock never sees a half-written bundle.
        let staging = directory.appendingPathComponent(".staging-\(folder.id.uuidString).app", isDirectory: true)
        try? fm.removeItem(at: staging)

        let contents = staging.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        try fm.copyItem(at: helperExecutable, to: macOS.appendingPathComponent("DokrFolder"))
        try infoPlist(for: folder, resident: resident).write(to: contents.appendingPathComponent("Info.plist"))
        try FolderIconRenderer.icns(for: folder).write(to: resources.appendingPathComponent("AppIcon.icns"))
        try JSONEncoder().encode(folder).write(to: resources.appendingPathComponent("folder.json"))
        try codesign(staging)

        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: url)
        }
        // Make LaunchServices (and the Dock's icon cache) pick up the new icon/name.
        LSRegisterURL(url as CFURL, true)
    }

    private func infoPlist(for folder: AppFolder, resident: Bool) throws -> Data {
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "DokrFolder",
            "CFBundleIdentifier": folder.bundleIdentifier,
            "CFBundleName": folder.name,
            "CFBundleDisplayName": folder.name,
            "CFBundleIconFile": "AppIcon",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            // Bumped on every build so caches treat it as a new version.
            "CFBundleVersion": String(Int(Date().timeIntervalSince1970)),
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            "DokrResident": resident,
            "NSHighResolutionCapable": true,
        ]
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    /// Ad-hoc signature: required to run on Apple silicon. Locally created files carry no
    /// quarantine flag, so Gatekeeper doesn't prompt.
    private func codesign(_ bundle: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FolderBundleBuilderError.codesignFailed(output)
        }
    }
}

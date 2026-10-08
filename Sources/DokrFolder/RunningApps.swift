import AppKit
import DokrCore
import DokrKit

/// Live set of running apps, for the Dock-style "open" dots in the popup.
@MainActor
final class RunningApps: ObservableObject {
    @Published private(set) var bundleIdentifiers: Set<String> = []
    @Published private(set) var paths: Set<String> = []

    /// Called after every refresh (app launched or quit).
    var onChange: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications
        bundleIdentifiers = Set(apps.compactMap(\.bundleIdentifier))
        paths = Set(apps.compactMap { $0.bundleURL?.standardizedFileURL.path })
        onChange?()
    }

    /// Running processes of `app` (matched like `isRunning`).
    func instances(of app: AppEntry) -> [NSRunningApplication] {
        let path = app.resolvedURL?.standardizedFileURL.path ?? app.path
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.path == path
                || (app.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier)
        }
    }

    func isRunning(_ app: AppEntry) -> Bool {
        if paths.contains(app.resolvedURL?.standardizedFileURL.path ?? app.path) {
            return true
        }
        return app.bundleIdentifier.map { bundleIdentifiers.contains($0) } ?? false
    }
}

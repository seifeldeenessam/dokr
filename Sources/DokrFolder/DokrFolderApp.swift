import AppKit
import DokrCore
import DokrKit
import os
import SwiftUI

/// Runs inside every generated folder `.app`. Clicking the Dock tile shows the folder's apps in
/// a popup next to the Dock; picking one launches it.
///
/// Resident mode (Info.plist `DokrResident`, or `--resident`): stays running in the background
/// and flips between a regular app (Dock shows the "open" dot under the folder) while any of its
/// apps are running and an accessory app (no dot) otherwise. Without it, quits after each use.
///
/// `--background`: start without showing the popup (used at login and after Apply).
///
/// Dev: `swift run DokrFolder --config path/to/folder.json [--resident]`
@main
enum DokrFolderMain {
    @MainActor private static let delegate = FolderAppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class FolderAppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.seifeldeenessam.dokr", category: "folder")
    private let running = RunningApps()

    private var folder = AppFolder(name: "")
    private var isResident = false
    private var panel: FolderPanel?
    private var shownAt = Date.distantFuture
    private var observers: [Any] = []

    /// Activation and focus shuffle right after the Dock launches/activates us; ignore close
    /// triggers from that window so the popup doesn't vanish immediately.
    private func isSettled(_ grace: TimeInterval) -> Bool {
        Date().timeIntervalSince(shownAt) > grace
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let folder = loadFolder() else {
            log.error("No folder.json found; quitting")
            NSSound.beep()
            NSApp.terminate(nil)
            return
        }
        self.folder = folder

        let args = CommandLine.arguments
        isResident = args.contains("--resident")
            || (Bundle.main.object(forInfoDictionaryKey: "DokrResident") as? Bool) == true

        running.onChange = { [weak self] in self?.updateDockIndicator() }
        updateDockIndicator()
        installCloseTriggers()

        if args.contains("--background") {
            if !isResident { NSApp.terminate(nil) }
        } else {
            show()
        }
    }

    /// Clicking the Dock tile toggles the popup.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel == nil {
            show()
        } else if isSettled(0.4) {
            close(reason: "Dock icon clicked again")
        } else {
            log.debug("Ignored reopen right after showing")
        }
        return false
    }

    // MARK: Dock indicator

    /// The Dock draws the "open" dot under our tile only while we're a regular app.
    private func updateDockIndicator() {
        let anyOpen = folder.apps.contains { running.isRunning($0) }
        let policy: NSApplication.ActivationPolicy = isResident && anyOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        log.debug("Activation policy -> \(policy == .regular ? "regular" : "accessory", privacy: .public)")
    }

    // MARK: Popup

    private func loadFolder() -> AppFolder? {
        let args = CommandLine.arguments
        let url: URL?
        if let i = args.firstIndex(of: "--config"), i + 1 < args.count {
            url = URL(fileURLWithPath: args[i + 1])
        } else {
            url = Bundle.main.url(forResource: "folder", withExtension: "json")
        }
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppFolder.self, from: data)
    }

    private func show() {
        let dock = DockSettings.current()
        let mouse = NSEvent.mouseLocation
        let hosting = NSHostingView(rootView: FolderGridView(
            folder: folder,
            running: running,
            showsRunningIndicators: dock.showsIndicators,
            onAction: { [weak self] app, action in self?.perform(action, on: app) },
            onEdit: { [weak self] in self?.openInDokr() },
            onClose: { [weak self] in self?.close(reason: "Esc") }
        ))
        var size = hosting.fittingSize
        switch dock.edge {
        case .bottom: size.height += CalloutView.tailLength
        case .left, .right: size.width += CalloutView.tailLength
        }

        let frame = PopupPlacement.frame(for: size, near: mouse, dock: dock)
        let background = CalloutView(
            frame: NSRect(origin: .zero, size: size),
            edge: dock.edge,
            tailPosition: PopupPlacement.tailPosition(in: frame, mouse: mouse, dock: dock, margin: CalloutView.tailMargin),
            content: hosting
        )

        // Non-activating: the panel takes key (Esc, hover) without having to win app activation.
        let panel = FolderPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.close(reason: "Esc") }
        self.panel = panel

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        // The shadow follows the callout's shape (tail included), not the window rectangle.
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        shownAt = Date()
        log.debug("Shown \(self.folder.name, privacy: .public) at \(NSStringFromRect(panel.frame), privacy: .public); dock \(String(describing: dock), privacy: .public)")
    }

    private func installCloseTriggers() {
        // Clicks delivered to other apps (anywhere outside the popup, incl. the Dock).
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.panel != nil, self.isSettled(0.25) else { return }
                    self.close(reason: "click outside")
                }
            }
        ) {
            observers.append(monitor)
        }

        // Cmd-Tab / another app coming forward.
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let name = app?.localizedName ?? "?"
            Task { @MainActor [weak self] in
                guard let self, self.panel != nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
                guard self.isSettled(1.0) else {
                    self.log.debug("Ignored early activation of \(name, privacy: .public)")
                    return
                }
                self.close(reason: "\(name) activated")
            }
        }
        observers.append(token)
    }

    private func perform(_ action: AppAction, on app: AppEntry) {
        switch action {
        case .open:
            open(app)
        case .showInFinder:
            guard let url = app.resolvedURL else { return NSSound.beep() }
            finish { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .quit:
            running.instances(of: app).forEach { $0.terminate() }
        case .forceQuit:
            running.instances(of: app).forEach { $0.forceTerminate() }
        case .remove:
            // Dokr rebuilds this folder app and the Dock (which relaunches this helper).
            openLink(.removeApp(app.id, from: folder.id), activates: false)
        }
    }

    /// Closes the popup, runs `work`, then quits unless resident.
    private func finish(_ work: () -> Void) {
        dismissPanel()
        work()
        if !isResident { NSApp.terminate(nil) }
    }

    private func open(_ app: AppEntry) {
        guard let url = app.resolvedURL else {
            NSSound.beep()
            return
        }
        open(url: url)
    }

    /// Opens Dokr with this folder selected.
    private func openInDokr() {
        openLink(.showFolder(folder.id), activates: true)
    }

    /// Closes the popup and hands `link` to Dokr via its `dokr://` URL scheme.
    private func openLink(_ link: DokrLink, activates: Bool) {
        dismissPanel()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        let resident = isResident
        NSWorkspace.shared.open(link.url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { NSAlert(error: error).runModal() }
                if !resident { NSApp.terminate(nil) }
            }
        }
    }

    private func open(url: URL) {
        dismissPanel()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let resident = isResident
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { NSAlert(error: error).runModal() }
                if !resident { NSApp.terminate(nil) }
            }
        }
    }

    private func close(reason: String) {
        guard panel != nil else { return }
        log.info("Closing: \(reason, privacy: .public)")
        dismissPanel()
        if !isResident {
            NSApp.terminate(nil)
        } else if NSApp.isActive {
            // The Dock click activated us; hand focus back to the previous app.
            NSApp.hide(nil)
        }
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        panel = nil
        shownAt = .distantFuture
    }
}

final class FolderPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

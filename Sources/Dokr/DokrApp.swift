import AppKit
import SwiftUI

@main
enum DokrMain {
    @MainActor static func main() {
        // Login item (see LoginAgent): start the folder helpers, no UI.
        if CommandLine.arguments.contains("--launch-folders") {
            if FolderLauncher.indicatorsEnabled {
                FolderLauncher.launchHelpers(for: FolderStore().load())
            }
            return
        }
        DokrApp.main()
    }
}

struct DokrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FoldersViewModel()

    var body: some Scene {
        Window("Dokr", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Folder") { model.addFolder() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Apply to Dock") { model.apply() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Revert Changes") { model.revert() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle / Info.plist).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

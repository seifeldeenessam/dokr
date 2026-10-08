import AppKit
import DokrCore
import DokrKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FoldersViewModel: ObservableObject {
    @Published var folders: [AppFolder]
    @Published private(set) var appliedFolders: [AppFolder]
    @Published var selection: AppFolder.ID?
    @Published var errorMessage: String?
    @Published private(set) var isApplying = false

    /// Remove an app's own Dock icon when it's put in a folder (like moving it on iOS).
    @Published var hideGroupedApps: Bool {
        didSet { UserDefaults.standard.set(hideGroupedApps, forKey: "hideGroupedApps") }
    }

    /// Keep folder helpers running so the Dock shows an "open" dot under a folder while any of
    /// its apps are running (and the popup opens instantly).
    @Published var showFolderIndicators: Bool {
        didSet { UserDefaults.standard.set(showFolderIndicators, forKey: FolderLauncher.indicatorsDefaultsKey) }
    }

    private let store = FolderStore()
    private let builder = FolderBundleBuilder()
    private let dock = DockPreferences()

    init() {
        let saved = FolderStore().load()
        folders = saved
        appliedFolders = saved
        selection = saved.first?.id
        hideGroupedApps = UserDefaults.standard.bool(forKey: "hideGroupedApps")
        showFolderIndicators = FolderLauncher.indicatorsEnabled
    }

    var hasChanges: Bool { folders != appliedFolders }

    // MARK: Folders

    func addFolder() {
        var name = "New Folder"
        var n = 2
        while folders.contains(where: { $0.name == name }) {
            name = "New Folder \(n)"
            n += 1
        }
        let folder = AppFolder(name: name)
        folders.append(folder)
        selection = folder.id
    }

    func select(_ id: AppFolder.ID) {
        guard folders.contains(where: { $0.id == id }) else { return }
        selection = id
    }

    func handle(_ link: DokrLink) {
        switch link {
        case .showFolder(let id):
            select(id)
        case .removeApp(let appID, let id):
            removeAppFromDock(appID, from: id)
        }
    }

    /// Removes the app from the folder and re-applies the Dock right away, leaving any other
    /// unsaved edits pending.
    func removeAppFromDock(_ appID: String, from id: AppFolder.ID) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].apps.removeAll { $0.id == appID }
        }
        select(id)
        guard let index = appliedFolders.firstIndex(where: { $0.id == id }),
              appliedFolders[index].apps.contains(where: { $0.id == appID })
        else { return }
        var target = appliedFolders
        target[index].apps.removeAll { $0.id == appID }
        apply(target)
    }

    func deleteFolder(_ id: AppFolder.ID) {
        folders.removeAll { $0.id == id }
        if selection == id { selection = folders.first?.id }
    }

    func moveFolders(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
    }

    func binding(for id: AppFolder.ID) -> Binding<AppFolder>? {
        guard let initial = folders.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.folders.first { $0.id == id } ?? initial },
            set: { newValue in
                if let index = self.folders.firstIndex(where: { $0.id == id }) {
                    self.folders[index] = newValue
                }
            }
        )
    }

    // MARK: Apps

    func add(_ apps: [AppEntry], to id: AppFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        for app in apps where !folders[index].apps.contains(where: { $0.id == app.id }) {
            folders[index].apps.append(app)
        }
    }

    func chooseApps(for id: AppFolder.ID) {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to Folder"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            add(panel.urls.compactMap(AppEntry.init(appURL:)), to: id)
        }
    }

    func handleDrop(_ providers: [NSItemProvider], into id: AppFolder.ID) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, let app = AppEntry(appURL: url) else { return }
                Task { @MainActor [weak self] in self?.add([app], to: id) }
            }
        }
        return !fileProviders.isEmpty
    }

    // MARK: Apply

    func revert() {
        folders = appliedFolders
        if let selection, !folders.contains(where: { $0.id == selection }) {
            self.selection = folders.first?.id
        }
    }

    func apply() {
        apply(folders)
    }

    /// Writes `target` to the Dock and store; it becomes `appliedFolders`.
    private func apply(_ target: [AppFolder]) {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            // Running helpers would keep showing the old folder until relaunched.
            FolderLauncher.terminateRunningHelpers()

            let bundles = try builder.build(target, resident: showFolderIndicators)
            let docked = target.filter(\.showInDock)
            let items = docked.compactMap { folder in
                bundles[folder.id].map {
                    DockAppsCodec.Item(path: $0.path, label: folder.name, bundleIdentifier: folder.bundleIdentifier)
                }
            }
            let tiles = DockAppsCodec.sync(
                dock.tiles(for: DockAppsCodec.persistentAppsKey),
                items: items,
                managedDirectory: FolderStore.foldersDirectory.path,
                hiding: hideGroupedApps ? docked.flatMap(\.apps) : []
            )
            try dock.setTiles(tiles, for: DockAppsCodec.persistentAppsKey)
            try store.save(target)
            try dock.restartDock()
            appliedFolders = target

            if showFolderIndicators {
                try LoginAgent.install()
                FolderLauncher.launchHelpers(for: target)
            } else {
                LoginAgent.uninstall()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import AppKit
import DokrCore
import DokrKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: FoldersViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.folders) { folder in
                    Label {
                        Text(folder.name)
                            .foregroundStyle(folder.showInDock ? .primary : .secondary)
                    } icon: {
                        Image(nsImage: FolderIconRenderer.image(for: folder, size: 22))
                    }
                    .tag(folder.id)
                    .contextMenu {
                        Button("Delete Folder", role: .destructive) { model.deleteFolder(folder.id) }
                    }
                }
                .onMove(perform: model.moveFolders)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom, spacing: 0) { attribution }
            .toolbar {
                ToolbarItem {
                    Button(action: model.addFolder) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .help("New Folder (⌘N)")
                }
            }
        } detail: {
            Group {
                if let id = model.selection, let folder = model.binding(for: id) {
                    FolderEditor(folder: folder)
                        .id(id)
                } else {
                    emptyState
                }
            }
            // Bottom bar belongs to the detail column; spanning the whole split view
            // breaks the sidebar's full-height layout on macOS 26.
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .frame(minWidth: 760, minHeight: 480)
        // From the folder popups (title click, "Remove from Folder").
        .onOpenURL { url in
            if let link = DokrLink(url: url) { model.handle(link) }
        }
        .alert("Couldn't update the Dock", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Group your apps into Dock folders")
                .font(.title3.weight(.semibold))
            Text("Create a folder, add apps, then Apply to Dock.")
                .foregroundStyle(.secondary)
            Button("New Folder", action: model.addFolder)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var attribution: some View {
        Link("Made by Seif Essam", destination: URL(string: "https://seifessam.com")!)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("seifessam.com")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Remove grouped apps' own Dock icons", isOn: $model.hideGroupedApps)
                    .help("When applying, apps that are inside a folder are removed from the Dock (they stay installed).")
                Toggle("Show open dot under folders", isOn: $model.showFolderIndicators)
                    .help("Keeps a tiny helper running per folder so the Dock shows a dot while any of its apps are open. Takes effect on Apply.")
            }
            Spacer()
            if model.hasChanges {
                Text("Unsaved changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Revert", action: model.revert)
                .disabled(!model.hasChanges)
            Button("Apply to Dock", action: model.apply)
                .disabled(model.isApplying)
        }
        .padding(12)
        .background(.bar)
    }
}

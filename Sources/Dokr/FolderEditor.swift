import AppKit
import DokrCore
import DokrKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderEditor: View {
    @Binding var folder: AppFolder
    @EnvironmentObject private var model: FoldersViewModel
    @State private var isPickerPresented = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if folder.apps.isEmpty {
                emptyApps
            } else {
                List {
                    ForEach(folder.apps) { app in
                        AppRow(app: app) {
                            folder.apps.removeAll { $0.id == app.id }
                        }
                    }
                    .onMove { folder.apps.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            HStack {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Add Apps…", systemImage: "plus")
                }
                Button("Choose in Finder…") { model.chooseApps(for: folder.id) }
                Spacer()
                Text("Drag to reorder · Drop apps from Finder · First 9 appear on the icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { model.handleDrop($0, into: folder.id) }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            AppPickerSheet(existing: Set(folder.apps.map(\.id))) { picked in
                model.add(picked, to: folder.id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: FolderIconRenderer.image(for: folder, size: 112))
                .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Folder name", text: $folder.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold))
                Toggle("Show in Dock", isOn: $folder.showInDock)
                Text(folder.apps.count == 1 ? "1 app" : "\(folder.apps.count) apps")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyApps: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No apps yet")
                .font(.headline)
            Text("Click Add Apps… or drop apps here from Finder.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}

private struct AppRow: View {
    let app: AppEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name)
                    if app.resolvedURL == nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("This app can't be found")
                    }
                }
                Text((app.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove from folder")
        }
        .padding(.vertical, 2)
    }
}

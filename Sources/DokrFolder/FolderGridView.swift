import DokrCore
import DokrKit
import SwiftUI

/// Right-click menu actions on an app in the popup.
enum AppAction {
    case open, showInFinder, quit, forceQuit, remove
}

/// Laid out like a Dock stack in grid view: title and app icons with full-size labels.
struct FolderGridView: View {
    let folder: AppFolder
    @ObservedObject var running: RunningApps
    let showsRunningIndicators: Bool
    let onAction: (AppEntry, AppAction) -> Void
    let onEdit: () -> Void
    let onClose: () -> Void

    private let cellWidth: CGFloat = 112
    private let cellHeight: CGFloat = 112
    private let spacing: CGFloat = 4
    private let maxVisibleRows = 4

    private var itemCount: Int { folder.apps.count }

    private var columns: Int {
        switch itemCount {
        case ...4: return max(itemCount, 1)
        case ...9: return 3
        case ...16: return 4
        case ...25: return 5
        default: return 6
        }
    }

    private var rows: Int { (itemCount + columns - 1) / columns }

    var body: some View {
        VStack(spacing: 10) {
            FolderTitle(name: folder.name, action: onEdit)

            if folder.apps.isEmpty {
                Text("This folder is empty.\nAdd apps to it in Dokr.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if rows > maxVisibleRows {
                ScrollView(showsIndicators: true) { grid }
                    .frame(width: gridWidth, height: CGFloat(maxVisibleRows) * (cellHeight + spacing))
            } else {
                grid
            }
        }
        .padding(.top, 12)
        .padding([.horizontal, .bottom], 18)
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private func menu(for app: AppEntry, isRunning: Bool) -> some View {
        Button("Open") { onAction(app, .open) }
        Button("Show in Finder") { onAction(app, .showInFinder) }
            .disabled(app.resolvedURL == nil)
        Divider()
        Button("Remove from \u{201C}\(folder.name)\u{201D}") { onAction(app, .remove) }
        if isRunning {
            Divider()
            Button("Quit") { onAction(app, .quit) }
            Button("Force Quit") { onAction(app, .forceQuit) }
        }
    }

    private var gridWidth: CGFloat {
        CGFloat(columns) * cellWidth + CGFloat(columns - 1) * spacing
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(folder.apps) { app in
                let isRunning = running.isRunning(app)
                GridCell(
                    title: app.name,
                    height: cellHeight,
                    isRunning: showsRunningIndicators && isRunning,
                    action: { onAction(app, .open) }
                ) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                }
                .contextMenu { menu(for: app, isRunning: isRunning) }
            }
        }
        .frame(width: gridWidth)
    }
}

/// The folder name; clicking it opens the folder in Dokr.
private struct FolderTitle: View {
    let name: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Edit in Dokr")
        .accessibilityLabel(name)
        .accessibilityHint("Opens this folder in Dokr")
    }
}

private struct GridCell<Icon: View>: View {
    let title: String
    let height: CGFloat
    let isRunning: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon()
                    .frame(width: 72, height: 72)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                // Dock-style "open" dot; space is always reserved so rows stay aligned.
                Circle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .opacity(isRunning ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isRunning ? "\(title) (open)" : title)
        .accessibilityLabel(title)
        .accessibilityValue(isRunning ? "Open" : "")
    }
}

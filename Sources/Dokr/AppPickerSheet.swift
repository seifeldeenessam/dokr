import DokrCore
import DokrKit
import SwiftUI

/// Searchable, multi-select list of installed apps.
struct AppPickerSheet: View {
    let existing: Set<String>
    let onAdd: ([AppEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [AppEntry] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var selected: [AppEntry] = []

    private var filtered: [AppEntry] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    row(app)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text(selected.isEmpty ? "Select apps to add" : "\(selected.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onAdd(selected)
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: 540)
        .task {
            apps = await Task.detached(priority: .userInitiated) { InstalledApps.scan() }.value
            isLoading = false
        }
    }

    private func row(_ app: AppEntry) -> some View {
        let alreadyAdded = existing.contains(app.id)
        let isSelected = selected.contains { $0.id == app.id }

        return Button {
            if isSelected {
                selected.removeAll { $0.id == app.id }
            } else {
                selected.append(app)
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(app.name)
                Spacer()
                if alreadyAdded {
                    Text("In folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
    }
}

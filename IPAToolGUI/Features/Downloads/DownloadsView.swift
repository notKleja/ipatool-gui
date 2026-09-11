import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @State private var detailItem: DownloadItem?

    var body: some View {
        Group {
            if appState.downloads.items.isEmpty {
                EmptyStateView("No Downloads", message: "Packages you download will appear here and stay in the list between launches.", systemImage: "arrow.down.circle")
            } else {
                List {
                    if !appState.downloads.activeItems.isEmpty {
                        Section("In Progress") {
                            ForEach(appState.downloads.activeItems) { item in
                                DownloadRowView(item: item, showDetails: { detailItem = $0 })
                            }
                        }
                    }
                    if !appState.downloads.finishedItems.isEmpty {
                        Section("History") {
                            ForEach(appState.downloads.finishedItems) { item in
                                DownloadRowView(item: item, showDetails: { detailItem = $0 })
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.open(appState.settings.downloadDirectory)
                } label: {
                    Label("Open Download Folder", systemImage: "folder")
                }
                Button {
                    appState.downloads.clearFinished()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(appState.downloads.finishedItems.isEmpty)
            }
        }
        .sheet(item: $detailItem) { item in
            DownloadDetailsView(item: item)
        }
    }
}

struct DownloadDetailsView: View {
    let item: DownloadItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.appName).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("State", item.state.displayName)
                row("Version", item.versionDescription)
                row("Platform", item.platform.displayName)
                row("Bundle ID", item.request.bundleID)
                row("App ID", String(item.request.appID))
                if let id = item.request.externalVersionID { row("External Version ID", id.rawValue) }
                if let destination = item.destinationURL { row("Destination", destination.path) }
                if let started = item.startedAt { row("Started", started.formatted(date: .abbreviated, time: .shortened)) }
                if let completed = item.completedAt { row("Finished", completed.formatted(date: .abbreviated, time: .shortened)) }
            }
            if let failure = item.failure {
                Divider()
                Text(failure.kind.title).font(.subheadline.weight(.semibold))
                Text(failure.kind.message).foregroundStyle(.secondary)
                ScrollView {
                    Text([failure.message, failure.details ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 100)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 560)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}

#Preview("Active and failed") {
    let state = AppState.preview()
    state.downloads.enqueue(Fixtures.downloadRequest())
    return DownloadsView().environment(state).frame(width: 760, height: 480)
}

#Preview("Empty") {
    DownloadsView().environment(AppState.preview()).frame(width: 760, height: 480)
}

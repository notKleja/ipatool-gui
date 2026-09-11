import SwiftUI

struct VersionHistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let app: AppStoreApp
    let platform: AppPlatform
    @State private var model: VersionHistoryViewModel?
    @State private var selection: ExternalVersionID?
    @State private var showsExternalIDs = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version History").font(.headline)
                    Text("\(app.displayName) · \(platform.displayName)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let model, model.isLoadingList || model.isResolving {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.isLoadingList ? "Loading versions…" : "Resolving \(model.resolvedCount)/\(model.totalCount)…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            Divider()
            content
            Divider()
            HStack {
                Toggle("Show External Version IDs", isOn: $showsExternalIDs).toggleStyle(.checkbox)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 380, idealHeight: 460)
        .task {
            let vm = VersionHistoryViewModel(service: appState.service, appID: app.id)
            model = vm
            vm.load()
        }
        .onDisappear { model?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            if let error = model.error {
                EmptyStateView(error.kind.title, message: error.kind.message, systemImage: "exclamationmark.triangle") {
                    Button("Try Again") { model.load() }
                }
            } else if model.isLoadingList {
                ProgressView("Loading versions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                EmptyStateView("No Versions", message: "The App Store didn't return any historical builds for this app.", systemImage: "clock")
            } else {
                table(model)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func table(_ model: VersionHistoryViewModel) -> some View {
        Table(model.sortedRows, selection: $selection) {
            TableColumn("Version") { row in
                Text(row.displayVersion)
                    .foregroundStyle(row.version == nil ? .secondary : .primary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Released") { row in
                if let date = row.releaseDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                } else if case .pending = row.status {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 140)
            TableColumn(showsExternalIDs ? "External Version ID" : "") { row in
                if showsExternalIDs {
                    Text(row.externalID.rawValue).font(.body.monospaced()).foregroundStyle(.secondary)
                }
            }
            .width(showsExternalIDs ? 140 : 0)
            TableColumn("") { row in
                Button("Download") { download(row) }
                    .controlSize(.small)
                    .disabled(!canDownload(row))
                    .accessibilityLabel("Download version \(row.displayVersion)")
            }
            .width(90)
        }
        .contextMenu(forSelectionType: ExternalVersionID.self) { ids in
            if let id = ids.first, let row = model.rows.first(where: { $0.externalID == id }) {
                Button("Download This Version") { download(row) }.disabled(!canDownload(row))
                Divider()
                if let version = row.version { Button("Copy Version") { Pasteboard.copy(version.displayVersion) } }
                Button("Copy External Version ID") { Pasteboard.copy(row.externalID.rawValue) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = model.rows.first(where: { $0.externalID == id }), canDownload(row) {
                download(row)
            }
        }
    }

    private func canDownload(_ row: VersionRow) -> Bool {
        if case .failed = row.status { return false }
        return true
    }

    private func download(_ row: VersionRow) {
        let version = row.version ?? AppVersion(externalID: row.externalID, displayVersion: "", releaseDate: nil)
        var request = appState.makeDownloadRequest(app: app, platform: platform, version: version)
        if version.displayVersion.isEmpty { request.requestedVersion = nil }
        appState.requestDownload(request)
        dismiss()
    }
}

#Preview {
    VersionHistoryView(app: Fixtures.searchResults[0], platform: .iPhone)
        .environment(AppState.preview())
}

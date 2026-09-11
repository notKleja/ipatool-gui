import SwiftUI
import AppKit

struct DownloadRowView: View {
    @Environment(AppState.self) private var appState
    let item: DownloadItem
    var showDetails: (DownloadItem) -> Void
    @State private var metadata: AppMetadata?

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: metadata?.artworkURL, size: 40, platform: item.platform)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.appName).font(.body.weight(.medium)).lineLimit(1)
                    Text(item.versionDescription).font(.caption).foregroundStyle(.secondary)
                    PlatformBadge(platform: item.platform)
                }
                statusLine
                if item.state == .downloading || item.state == .acquiringLicense || item.state == .preparing {
                    if let progress = item.progress, item.state == .downloading {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .accessibilityValue("\(Int(progress * 100)) percent")
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            }
            Spacer()
            trailingActions
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenu }
        .task(id: item.request.appID) {
            guard appState.settings.metadataEnabled else { return }
            metadata = await appState.metadata.metadata(for: item.request.appID)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.state {
        case .queued:
            Text("Waiting to start").font(.caption).foregroundStyle(.secondary)
        case .preparing:
            Text("Preparing…").font(.caption).foregroundStyle(.secondary)
        case .acquiringLicense:
            Text("Acquiring license…").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            if let progress = item.progress {
                Text("Downloading… \(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Downloading…").font(.caption).foregroundStyle(.secondary)
            }
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(item.destinationURL?.lastPathComponent ?? "Completed")
                    .lineLimit(1).truncationMode(.middle)
                if !item.fileExists { Text("(file moved or deleted)").foregroundStyle(.secondary) }
                if item.licenseAcquired { Text("· License acquired").foregroundStyle(.secondary) }
            }
            .font(.caption)
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(item.failure?.kind.title ?? "Failed")
            }
            .font(.caption)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        switch item.state {
        case .queued, .preparing, .acquiringLicense, .downloading:
            Button {
                appState.downloads.cancel(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Cancel")
            .accessibilityLabel("Cancel download of \(item.appName)")
        case .completed:
            Button("Show in Finder") { reveal() }
                .controlSize(.small)
                .disabled(!item.fileExists)
        case .failed:
            HStack(spacing: 6) {
                Button("Retry") { appState.downloads.retry(id: item.id) }.controlSize(.small)
                Button("Show Details") { showDetails(item) }.controlSize(.small)
            }
        case .cancelled:
            Button("Download Again") { appState.downloads.retry(id: item.id) }.controlSize(.small)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if item.state.isActive {
            Button("Cancel") { appState.downloads.cancel(id: item.id) }
        }
        if item.state == .completed {
            Button("Reveal in Finder") { reveal() }.disabled(!item.fileExists)
            Button("Open Containing Folder") {
                if let url = item.destinationURL { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
            }
            Button("Copy Path") { if let url = item.destinationURL { Pasteboard.copy(url.path) } }
            Divider()
            Button("Download Again") { appState.downloads.downloadAgain(id: item.id) }
        }
        if item.state == .failed {
            Button("Retry") { appState.downloads.retry(id: item.id) }
            if item.failure?.kind == .licenseRequired, item.request.price <= 0 {
                Button("Get & Download") { appState.downloads.retry(id: item.id, acquireLicense: true) }
            }
            Button("Show Details") { showDetails(item) }
        }
        if item.state == .cancelled {
            Button("Download Again") { appState.downloads.retry(id: item.id) }
        }
        Divider()
        Button("Copy Bundle ID") { Pasteboard.copy(item.request.bundleID) }
        if item.state.isTerminal {
            Divider()
            Button("Remove from History") { appState.downloads.remove(id: item.id) }
        }
    }

    private func reveal() {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#Preview {
    List {
        DownloadRowView(item: Fixtures.activeDownload, showDetails: { _ in })
        DownloadRowView(item: Fixtures.failedDownload, showDetails: { _ in })
        DownloadRowView(item: Fixtures.completedDownload, showDetails: { _ in })
    }
    .environment(AppState.preview())
    .frame(width: 700)
}

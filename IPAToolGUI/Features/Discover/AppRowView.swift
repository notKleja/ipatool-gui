import SwiftUI

struct AppRowView: View {
    @Environment(AppState.self) private var appState
    let app: AppStoreApp
    let platform: AppPlatform
    var showsPurchaseDate = false
    @State private var metadata: AppMetadata?

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: metadata?.artworkURL, size: 44, platform: platform)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let developer = metadata?.developerName {
                        Text(developer).lineLimit(1)
                    } else {
                        Text(app.bundleID).lineLimit(1).truncationMode(.middle)
                    }
                    if !app.version.isEmpty {
                        Text("·")
                        Text(app.version)
                    }
                    if showsPurchaseDate, let date = app.purchaseDate {
                        Text("·")
                        Text("Acquired \(date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(app.priceDescription)
                .font(.caption.weight(.semibold))
                .foregroundStyle(app.isFree ? .secondary : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Button("Download") {
                appState.requestDownload(appState.makeDownloadRequest(app: app, platform: platform))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Download \(app.displayName)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .task(id: app.id) {
            guard appState.settings.metadataEnabled else { return }
            metadata = await appState.metadata.metadata(for: app.id)
        }
    }
}

#Preview {
    List {
        AppRowView(app: Fixtures.searchResults[0], platform: .iPhone)
        AppRowView(app: Fixtures.searchResults[4], platform: .iPad)
    }
    .environment(AppState.preview())
    .frame(width: 600)
}

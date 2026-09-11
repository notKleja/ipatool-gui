import SwiftUI

struct AppDetailView: View {
    @Environment(AppState.self) private var appState
    let app: AppStoreApp
    @State var platform: AppPlatform
    @State private var metadata: AppMetadata?
    @State private var isVersionHistoryPresented = false

    init(app: AppStoreApp, platform: AppPlatform) {
        self.app = app
        _platform = State(initialValue: platform)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                metadataSection
                if let description = metadata?.description, !description.isEmpty {
                    Divider()
                    section("Description") {
                        Text(description)
                            .textSelection(.enabled)
                            .lineLimit(12)
                    }
                }
                if let notes = metadata?.releaseNotes, !notes.isEmpty {
                    Divider()
                    section("What's New in \(metadata?.latestVersion ?? app.version)") {
                        Text(notes).textSelection(.enabled).lineLimit(10)
                    }
                }
                if let screenshots = metadata?.screenshotURLs, !screenshots.isEmpty {
                    Divider()
                    section("Screenshots") { ScreenshotStrip(urls: screenshots) }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(app.displayName)
        .navigationSubtitle(metadata?.developerName ?? app.bundleID)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PlatformPicker(platform: $platform).pickerStyle(.menu)
            }
        }
        .sheet(isPresented: $isVersionHistoryPresented) {
            VersionHistoryView(app: app, platform: platform)
        }
        .task(id: app.id) {
            guard appState.settings.metadataEnabled else { return }
            metadata = await appState.metadata.metadata(for: app.id)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            AppIconView(url: metadata?.artworkURL, size: 112, platform: platform)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.displayName).font(.title.weight(.semibold))
                if let developer = metadata?.developerName {
                    Text(developer).font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if !app.version.isEmpty { Text("Version \(app.version)") }
                    PlatformBadge(platform: platform)
                    if let rating = metadata?.averageRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                    if let genre = metadata?.genre { Text(genre) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Button {
                        appState.requestDownload(appState.makeDownloadRequest(app: app, platform: platform))
                    } label: {
                        Label("Download Latest", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("d", modifiers: .command)

                    if app.isFree {
                        Button("Get & Download") {
                            appState.requestDownload(appState.makeDownloadRequest(app: app, platform: platform, acquireLicense: true))
                        }
                        .help("Acquire a free license with this Apple Account, then download.")
                    }
                    Button("Version History…") { isVersionHistoryPresented = true }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataSection: some View {
        section("Information") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                infoRow("Bundle ID", app.bundleID, copyable: true, monospaced: true)
                infoRow("App ID", String(app.id), copyable: true, monospaced: true)
                if !app.version.isEmpty { infoRow("Latest Version", app.version) }
                infoRow("Platform", "\(platform.displayName) · \(platform.operatingSystemName)")
                infoRow("Price", app.isFree ? "Free" : "\(app.priceDescription) — buy in the App Store before downloading")
                infoRow("Package", "\(platform.packageKind) (App Store package; may remain FairPlay-protected)")
                if let size = metadata?.fileSizeBytes {
                    infoRow("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
                if let minimum = metadata?.minimumOSVersion {
                    infoRow("Requires", "\(platform.operatingSystemName) \(minimum) or later")
                }
                if let store = metadata?.storeURL ?? URL(string: "https://apps.apple.com/app/id\(app.id)") {
                    GridRow {
                        Text("App Store").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Link("Open App Store page", destination: store)
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, copyable: Bool = false, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                if copyable {
                    Button { Pasteboard.copy(value) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy \(label)")
                        .accessibilityLabel("Copy \(label)")
                }
            }
            .contextMenu { Button("Copy \(label)") { Pasteboard.copy(value) } }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

struct ScreenshotStrip: View {
    let urls: [URL]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(urls.prefix(8), id: \.self) { url in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .accessibilityLabel("Screenshots")
    }
}

#Preview {
    NavigationStack {
        AppDetailView(app: Fixtures.searchResults[0], platform: .iPhone)
    }
    .environment(AppState.preview())
    .frame(width: 800, height: 600)
}

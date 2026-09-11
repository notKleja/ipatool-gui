import SwiftUI

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @State private var model: DiscoverViewModel?
    @State private var isSearchPresented = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Discover")
                .navigationDestination(for: AppStoreApp.self) { app in
                    AppDetailView(app: app, platform: model?.platform ?? appState.settings.defaultPlatform)
                }
        }
        .task {
            if model == nil {
                model = DiscoverViewModel(service: appState.service, metadata: appState.metadata,
                                          platform: appState.settings.defaultPlatform,
                                          limit: { [settings = appState.settings] in settings.searchLimit })
            }
        }
        .onChange(of: appState.searchFocusRequest) { _, _ in
            isSearchPresented = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            @Bindable var model = model
            Group {
                if !appState.auth.isSignedIn {
                    EmptyStateView("Sign in to Search", message: "The App Store search API needs a signed-in Apple Account.", systemImage: "person.crop.circle") {
                        Button("Sign In…") { appState.isSignInPresented = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if let error = model.error {
                    EmptyStateView(error.kind.title, message: error.kind.message, systemImage: "exclamationmark.triangle") {
                        HStack {
                            Button("Try Again") { model.retry() }
                            if error.kind == .notAuthenticated {
                                Button("Sign In…") { appState.isSignInPresented = true }
                            }
                        }
                    }
                } else if model.results.isEmpty {
                    if model.isSearching {
                        ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.hasSearched {
                        EmptyStateView("No Results", message: "No \(model.platform.displayName) apps matched “\(model.trimmedQuery)”.", systemImage: "magnifyingglass")
                    } else {
                        EmptyStateView("Search the App Store", message: "Find apps for \(model.platform.displayName), then download or inspect them.", systemImage: "magnifyingglass")
                    }
                } else {
                    resultsList(model)
                }
            }
            .searchable(text: $model.query, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search App Store")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PlatformPicker(platform: $model.platform)
                        .pickerStyle(.menu)
                        .frame(minWidth: 120)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func resultsList(_ model: DiscoverViewModel) -> some View {
        List(model.results) { app in
            NavigationLink(value: app) {
                AppRowView(app: app, platform: model.platform)
            }
            .contextMenu { AppContextMenu(app: app, platform: model.platform) }
        }
        .listStyle(.inset)
        .overlay(alignment: .top) {
            if model.isSearching {
                ProgressView().controlSize(.small).padding(6)
            }
        }
    }
}

/// Shared context menu for app rows in Discover and Library.
struct AppContextMenu: View {
    @Environment(AppState.self) private var appState
    let app: AppStoreApp
    let platform: AppPlatform
    var onVersionHistory: (() -> Void)?

    var body: some View {
        Button("Download Latest") {
            appState.requestDownload(appState.makeDownloadRequest(app: app, platform: platform))
        }
        if app.isFree {
            Button("Get & Download") {
                appState.requestDownload(appState.makeDownloadRequest(app: app, platform: platform, acquireLicense: true))
            }
        }
        if let onVersionHistory {
            Button("Version History…", action: onVersionHistory)
        }
        Divider()
        Button("Copy Bundle ID") { Pasteboard.copy(app.bundleID) }
        Button("Copy App ID") { Pasteboard.copy(String(app.id)) }
        Link("Open in App Store", destination: URL(string: "https://apps.apple.com/app/id\(app.id)")!)
    }
}

#Preview("Results") {
    DiscoverView().environment(AppState.preview(signedIn: true)).frame(width: 800, height: 500)
}

#Preview("Signed out") {
    DiscoverView().environment(AppState.preview(signedIn: false)).frame(width: 800, height: 500)
}

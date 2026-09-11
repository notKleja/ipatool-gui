import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var model: LibraryViewModel?
    @State private var versionHistoryApp: AppStoreApp?
    @State private var platform: AppPlatform = .iPhone
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Library")
                .navigationDestination(for: AppStoreApp.self) { app in
                    AppDetailView(app: app, platform: platform)
                }
        }
        .task {
            platform = appState.settings.defaultPlatform
            if model == nil {
                let vm = LibraryViewModel(service: appState.service, metadata: appState.metadata)
                model = vm
                if appState.auth.isSignedIn { vm.refresh() }
            }
        }
        .onChange(of: appState.auth.isSignedIn) { _, _ in
            model?.refresh()
        }
        .sheet(item: $versionHistoryApp) { app in
            VersionHistoryView(app: app, platform: platform)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            @Bindable var model = model
            Group {
                if !appState.auth.isSignedIn {
                    EmptyStateView("Sign in to view your library.", message: "Apps acquired with your Apple Account appear here.", systemImage: "person.crop.circle") {
                        Button("Sign In…") { appState.isSignInPresented = true }.buttonStyle(.borderedProminent)
                    }
                } else if let error = model.error, model.apps.isEmpty {
                    EmptyStateView(error.kind.title, message: error.kind.message, systemImage: "exclamationmark.triangle") {
                        Button("Try Again") { model.refresh() }
                    }
                } else if model.apps.isEmpty && model.isLoading {
                    ProgressView("Loading purchases…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.apps.isEmpty {
                    EmptyStateView("No Purchased Apps", message: "Apps acquired with this Apple Account will appear here.", systemImage: "square.grid.2x2") {
                        Button("Refresh") { model.refresh() }
                    }
                } else {
                    list(model)
                }
            }
            .searchable(text: $model.filter, placement: .toolbar, prompt: "Filter Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PlatformPicker(platform: $platform, label: "Download for").pickerStyle(.menu)
                        .help("Platform used when downloading from the Library")
                }
                ToolbarItem {
                    Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(!appState.auth.isSignedIn)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func list(_ model: LibraryViewModel) -> some View {
        List {
            ForEach(model.filteredApps) { app in
                NavigationLink(value: app) {
                    AppRowView(app: app, platform: platform, showsPurchaseDate: true)
                }
                .contextMenu {
                    AppContextMenu(app: app, platform: platform) { versionHistoryApp = app }
                }
                .onAppear { model.loadMoreIfNeeded(current: app) }
            }
            if model.hasMore && model.filter.isEmpty {
                HStack {
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Load More") { model.loadMore() }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            if !model.apps.isEmpty {
                Text("\(model.apps.count) of \(model.totalCount) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.inset)
    }
}

#Preview("Signed in") {
    LibraryView().environment(AppState.preview()).frame(width: 800, height: 500)
}

#Preview("Signed out") {
    LibraryView().environment(AppState.preview(signedIn: false)).frame(width: 800, height: 500)
}

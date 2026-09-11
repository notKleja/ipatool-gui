import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView()
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 520)
        .sheet(isPresented: $appState.isSignInPresented) {
            SignInSheet()
        }
        .engineErrorAlert($appState.presentedError)
        .alert("Replace Existing File?", isPresented: Binding(get: { appState.pendingConflict != nil }, set: { if !$0 { appState.pendingConflict = nil } }), presenting: appState.pendingConflict) { conflict in
            Button("Replace", role: .destructive) { appState.resolveConflict(conflict, keepBoth: false) }
            Button("Keep Both") { appState.resolveConflict(conflict, keepBoth: true) }
            Button("Cancel", role: .cancel) { appState.pendingConflict = nil }
        } message: { conflict in
            Text("“\(conflict.existingFile.lastPathComponent)” already exists in \(conflict.existingFile.deletingLastPathComponent().lastPathComponent).")
        }
        .alert("App Not Acquired", isPresented: Binding(get: { appState.downloads.licensePrompt != nil }, set: { if !$0 { appState.downloads.licensePrompt = nil } }), presenting: appState.downloads.licensePrompt) { item in
            Button("Get & Download") {
                appState.downloads.retry(id: item.id, acquireLicense: true)
                appState.downloads.licensePrompt = nil
            }
            Button("Cancel", role: .cancel) { appState.downloads.licensePrompt = nil }
        } message: { item in
            Text("“\(item.appName)” hasn't been acquired by this Apple Account.\n\nAcquire it from the App Store and continue downloading?")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.engine {
        case .detecting:
            ProgressView("Looking for ipatool…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing, .invalid:
            EngineMissingView()
        case .ready, .unsupported:
            switch appState.selection ?? .discover {
            case .discover: DiscoverView()
            case .library: LibraryView()
            case .downloads: DownloadsView()
            }
        }
    }
}

#Preview("Signed in") {
    MainWindow().environment(AppState.preview(signedIn: true))
}

#Preview("Engine missing") {
    MainWindow().environment(AppState.preview(signedIn: false, engine: .missing))
}

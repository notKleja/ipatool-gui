import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selection) {
            ForEach(SidebarSection.allCases) { section in
                Label {
                    HStack {
                        Text(section.title)
                        if section == .downloads, appState.downloads.activeCount > 0 {
                            Spacer()
                            Text("\(appState.downloads.activeCount)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .accessibilityLabel("\(appState.downloads.activeCount) active downloads")
                        }
                    }
                } icon: {
                    Image(systemName: section.symbol)
                }
                .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            AccountFooter()
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(.bar)
    }
}

struct AccountFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.auth.state {
        case .signedIn(let account):
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.email).font(.callout).lineLimit(1).truncationMode(.middle)
                    Text("Signed In").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .contextMenu {
                Button("Sign Out…") {
                    Task { do { try await appState.auth.signOut() } catch { appState.present(error) } }
                }
            }
        case .checking, .unknown:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking account…").font(.callout).foregroundStyle(.secondary)
            }
        case .signedOut:
            Button {
                appState.isSignInPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sign In").font(.callout)
                        Text("Apple Account").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .disabled(!appState.engine.isUsable)
        }
    }
}

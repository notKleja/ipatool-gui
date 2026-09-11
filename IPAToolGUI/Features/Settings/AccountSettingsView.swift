import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isSigningOut = false
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section("Apple Account") {
                switch appState.auth.state {
                case .signedIn(let account):
                    LabeledContent("Name", value: account.name.isEmpty ? "—" : account.name)
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Status") {
                        Label("Signed In", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    HStack {
                        Button("Sign Out…") { confirmSignOut = true }.disabled(isSigningOut)
                        if isSigningOut { ProgressView().controlSize(.small) }
                    }
                    Text("Signing out revokes the App Store session ipatool stores in your Keychain. It does not sign you out of iCloud or your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                case .signedOut:
                    LabeledContent("Status", value: "Signed Out")
                    Button("Sign In…") { appState.isSignInPresented = true }
                        .disabled(!appState.engine.isUsable)
                    if let error = appState.auth.lastError, error.kind != .notAuthenticated {
                        Text(error.kind.message).font(.caption).foregroundStyle(.secondary)
                    }
                case .checking, .unknown:
                    LabeledContent("Status") {
                        HStack { ProgressView().controlSize(.small); Text("Checking…") }
                    }
                }
            }
            Section("Where credentials live") {
                Text("IPATool never stores your Apple Account password or verification codes. ipatool keeps its own session token in the macOS Keychain (service “ipatool-auth.service”) and cookies in ~/.ipatool.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out of the App Store?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { signOut() }
        } message: {
            Text("ipatool's stored App Store credentials will be revoked. You'll need to sign in again to search or download.")
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            defer { isSigningOut = false }
            do { try await appState.auth.signOut() } catch { appState.present(error) }
        }
    }
}

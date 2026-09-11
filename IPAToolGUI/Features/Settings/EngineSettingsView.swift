import SwiftUI
import AppKit

struct EngineSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmInstall = false

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("ipatool") {
                LabeledContent("Binary") {
                    Text(appState.engine.executable?.path ?? settings.customBinaryPath ?? "Not found")
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version") {
                    Text(appState.engine.version.map { "ipatool \($0.description)" } ?? "—").foregroundStyle(.secondary)
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        statusIcon
                        Text(appState.engine.statusText)
                    }
                }
                if case .ready(_, let version) = appState.engine, !version.isRecommendedOrNewer {
                    Text("ipatool \(IPAToolVersion.recommended.description) or newer is recommended; some platforms may be unavailable with older releases.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Detect Automatically") {
                        settings.customBinaryPath = nil
                        Task { await appState.detectEngine() }
                    }
                    Button("Select Binary…") { chooseBinary() }
                    if !appState.engine.isUsable, appState.installer?.homebrewURL != nil {
                        Button("Install with Homebrew…") { confirmInstall = true }
                            .disabled(appState.installer?.isRunning == true)
                    }
                    Spacer()
                    Link("ipatool on GitHub", destination: URL(string: "https://github.com/majd/ipatool")!)
                        .font(.callout)
                }
            }
            Section("Diagnostics") {
                Toggle("Enable verbose ipatool logging", isOn: $settings.verboseLogging)
                Text("Adds --verbose to every ipatool invocation. Secrets are redacted before anything is recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.verboseLogging) { _, _ in appState.applyEngineConfiguration() }
        .confirmationDialog("Install ipatool with Homebrew?", isPresented: $confirmInstall) {
            Button("Install") { appState.installer?.installWithHomebrew { await appState.detectEngine() } }
        } message: {
            Text("This runs “brew install ipatool” using your Homebrew installation.")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.engine {
        case .detecting: ProgressView().controlSize(.mini)
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unsupported: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .invalid, .missing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the ipatool executable"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await appState.selectBinary(url) }
        }
    }
}

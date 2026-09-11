import SwiftUI
import AppKit

/// Friendly empty state shown when no working ipatool binary is available.
struct EngineMissingView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmInstall = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(title, message: message, systemImage: "terminal") {
                VStack(spacing: 12) {
                    HStack {
                        if let installer = appState.installer, installer.homebrewURL != nil {
                            Button("Install with Homebrew…") { confirmInstall = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(installer.isRunning)
                        } else {
                            Button("Download ipatool…") { openURL(EngineInstaller.releasesURL) }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Detect Again") { Task { await appState.detectEngine() } }
                            .disabled(appState.installer?.isRunning == true)
                        Button("Select Binary…") { chooseBinary() }
                    }
                    if appState.installer?.homebrewURL != nil {
                        Button("Download from GitHub instead") { openURL(EngineInstaller.releasesURL) }
                            .buttonStyle(.link)
                            .font(.callout)
                    } else {
                        Text("Or install with Homebrew: brew install ipatool")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            if let installer = appState.installer {
                installProgress(installer)
            }
        }
        .confirmationDialog("Install ipatool with Homebrew?", isPresented: $confirmInstall) {
            Button("Install") {
                appState.installer?.installWithHomebrew { await appState.detectEngine() }
            }
        } message: {
            Text("This runs “brew install ipatool” using your Homebrew installation. Nothing else is changed.")
        }
    }

    @ViewBuilder
    private func installProgress(_ installer: EngineInstaller) -> some View {
        switch installer.state {
        case .idle:
            EmptyView()
        case .running:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing ipatool with Homebrew…").font(.callout)
                    Button("Cancel") { installer.cancel() }.controlSize(.small)
                }
                transcriptView(installer)
            }
        case .failed(let reason):
            VStack(spacing: 8) {
                Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                transcriptView(installer)
            }
        case .succeeded:
            Label("ipatool installed. Re-detecting…", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        }
    }

    private func transcriptView(_ installer: EngineInstaller) -> some View {
        ScrollView {
            Text(installer.transcript.isEmpty ? "Waiting for Homebrew…" : installer.transcript)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxWidth: 560)
        .frame(height: 140)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 16)
    }

    private var title: String {
        if case .invalid = appState.engine { return "ipatool Can't Be Used" }
        return "ipatool Is Required"
    }

    private var message: String {
        switch appState.engine {
        case .invalid(let url, let reason):
            "\(url.path)\n\(reason)"
        default:
            "IPATool is a native front end for the open-source ipatool engine. Install it, then let the app detect it or choose the binary yourself."
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose the ipatool executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await appState.selectBinary(url) }
        }
    }
}

#Preview {
    EngineMissingView().environment(AppState.preview(engine: .missing))
}

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Diagnostics") {
                Toggle("Show raw command diagnostics", isOn: $settings.showRawDiagnostics)
                HStack {
                    Button("Copy Diagnostic Report") {
                        Pasteboard.copy(appState.diagnostics.report(engineStatus: appState.engineDescription,
                                                                    account: appState.auth.account?.email))
                    }
                    Button("Clear Log") { appState.diagnostics.clear() }
                        .disabled(appState.diagnostics.entries.isEmpty)
                }
                Text("Reports contain redacted command lines, exit codes and timings. They never include passwords, verification codes or session tokens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if settings.showRawDiagnostics {
                Section("Recent ipatool invocations") {
                    if appState.diagnostics.entries.isEmpty {
                        Text("Nothing recorded yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.diagnostics.entries.suffix(30).reversed()) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.command).font(.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                                HStack {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    Text("exit \(entry.exitCode.map(String.init) ?? "—")")
                                    Text(String(format: "%.2fs", entry.duration))
                                    if !entry.note.isEmpty { Text(entry.note).lineLimit(1) }
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Keychain") {
                Text("On macOS, ipatool stores its session in the login Keychain and may ask for permission the first time it runs from this app. Approve with “Always Allow” to avoid repeated prompts. The `--keychain-passphrase` option only applies to the file-based keyring on other platforms.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Downloads") {
                LabeledContent("Download location") {
                    HStack {
                        Text(settings.downloadDirectory.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseDirectory() }
                    }
                }
                Toggle("Reveal file in Finder after downloading", isOn: $settings.revealAfterDownload)
                Picker("If a file already exists", selection: $settings.conflictPolicy) {
                    ForEach(FileConflictPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Stepper("Maximum simultaneous downloads: \(settings.maxConcurrentDownloads)",
                        value: $settings.maxConcurrentDownloads, in: 1...4)
            }
            Section("Discover") {
                PlatformPicker(platform: $settings.defaultPlatform, label: "Default platform")
                Stepper("Search results per query: \(settings.searchLimit)", value: $settings.searchLimit, in: 5...100, step: 5)
                Toggle("Load icons and descriptions from Apple", isOn: $settings.metadataEnabled)
                TextField("Storefront country code", text: $settings.metadataCountry, prompt: Text("US"))
                    .frame(maxWidth: 220)
                    .disabled(!settings.metadataEnabled)
                Text("Used only for optional artwork and descriptions from Apple's public lookup service. Downloads never depend on it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.maxConcurrentDownloads) { _, _ in appState.applyEngineConfiguration() }
        .onChange(of: settings.revealAfterDownload) { _, _ in appState.applyEngineConfiguration() }
        .onChange(of: settings.conflictPolicy) { _, _ in appState.applyEngineConfiguration() }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.settings.downloadDirectory
        panel.message = "Choose where downloaded packages are saved"
        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.downloadDirectory = url
        }
    }
}

import SwiftUI

struct PlatformPicker: View {
    @Binding var platform: AppPlatform
    var label = "Platform"

    var body: some View {
        Picker(label, selection: $platform) {
            ForEach(AppPlatform.allCases) { platform in
                Label(platform.displayName, systemImage: platform.symbolName).tag(platform)
            }
        }
        .accessibilityLabel(label)
    }
}

struct PlatformBadge: View {
    let platform: AppPlatform

    var body: some View {
        Label(platform.displayName, systemImage: platform.symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

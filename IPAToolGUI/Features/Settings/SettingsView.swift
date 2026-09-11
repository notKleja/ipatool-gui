import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            EngineSettingsView()
                .tabItem { Label("ipatool", systemImage: "terminal") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
    }
}

#Preview {
    SettingsView().environment(AppState.preview())
}

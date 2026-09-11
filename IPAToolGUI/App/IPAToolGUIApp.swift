import SwiftUI

@main
struct IPAToolGUIApp: App {
    @State private var appState = AppState.live()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .task { await appState.startIfNeeded() }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Focus Search") { appState.searchFocusRequest += 1 }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { appState.selection = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Account") {
                if appState.auth.isSignedIn {
                    Button("Sign Out…") {
                        Task {
                            do { try await appState.auth.signOut() } catch { appState.present(error) }
                        }
                    }
                } else {
                    Button("Sign In…") { appState.isSignInPresented = true }
                        .disabled(!appState.engine.isUsable)
                }
                Divider()
                Button("Detect ipatool Again") { Task { await appState.detectEngine() } }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

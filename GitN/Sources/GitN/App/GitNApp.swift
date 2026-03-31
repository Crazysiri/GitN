import SwiftUI

@main
struct GitNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appModel = AppModel()
    @State private var themeManager = ThemeManager()
    @State private var updateCoordinator = UpdateCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(themeManager)
                .environment(updateCoordinator)
                .task {
                    updateCoordinator.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                Button("Version \(version)") {}
                    .disabled(true)
            }

            CommandGroup(replacing: .systemServices) {}

            CommandGroup(replacing: .newItem) {
                Button("Open Repository...") {
                    appModel.openRepository()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(!updateCoordinator.canCheckForUpdates)
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Picker("Theme", selection: Binding(
                    get: { themeManager.currentTheme },
                    set: { themeManager.currentTheme = $0 }
                )) {
                    Text("Dark").tag(AppTheme.dark)
                    Text("Light").tag(AppTheme.light)
                    Text("System").tag(AppTheme.system)
                }
            }

        }

        Settings {
            SettingsView()
                .environment(updateCoordinator)
        }
    }
}

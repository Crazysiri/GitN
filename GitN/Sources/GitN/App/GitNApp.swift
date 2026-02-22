import SwiftUI

@main
struct GitNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appModel = AppModel()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(themeManager)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Repository...") {
                    appModel.openRepository()
                }
                .keyboardShortcut("o", modifiers: .command)
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
    }
}

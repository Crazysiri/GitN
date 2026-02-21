import SwiftUI

@main
struct GitXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Repository...") {
                    appModel.openRepository()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

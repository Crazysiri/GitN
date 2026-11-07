import SwiftUI

@main
struct GitNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appModel = AppModel()
    @State private var updateCoordinator = UpdateCoordinator()

    var body: some Scene {
        WindowGroup(id: "repositories") {
            RepositoryWindowRoot(appDelegate: appDelegate)
                .environment(appModel)
                .environment(appDelegate.themeManager)
                .environment(updateCoordinator)
                .onOpenURL { url in
                    appDelegate.openMarkdown(url)
                }
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
                OpenRepositoryButton(appModel: appModel, appDelegate: appDelegate)
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
                    get: { appDelegate.themeManager.currentTheme },
                    set: { appDelegate.themeManager.currentTheme = $0 }
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

/// Keep the cold-launch scene available for subsequent URL events without
/// presenting a repository window. An explicit repository command reveals it.
private struct RepositoryWindowRoot: View {
    @ObservedObject private var appDelegate: AppDelegate
    @State private var isDocumentBootstrap: Bool

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        _isDocumentBootstrap = State(initialValue: appDelegate.openedDocumentDuringLaunch)
    }

    var body: some View {
        Group {
            if !isDocumentBootstrap || !appDelegate.openedDocumentDuringLaunch {
                ContentView()
            } else {
                Color.clear
                    .background(DocumentBootstrapWindowHider())
            }
        }
        .onChange(of: appDelegate.openedDocumentDuringLaunch) { _, documentRequested in
            if !documentRequested { isDocumentBootstrap = false }
        }
    }
}

private struct DocumentBootstrapWindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HidingView { HidingView() }
    func updateNSView(_ nsView: HidingView, context: Context) {}

    final class HidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.orderOut(nil)
            }
        }
    }
}

private struct OpenRepositoryButton: View {
    let appModel: AppModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Repository...") {
            appDelegate.allowRepositoryWindow()
            openWindow(id: "repositories")
            appModel.openRepository()
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

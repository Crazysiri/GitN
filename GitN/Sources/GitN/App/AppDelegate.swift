import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var localMonitor: Any?
    let themeManager = ThemeManager()
    private(set) lazy var markdownWindows = MarkdownWindowController(theme: themeManager)
    @Published private(set) var openedDocumentDuringLaunch = false

    func openMarkdown(_ url: URL) {
        openedDocumentDuringLaunch = true
        markdownWindows.open(url)
    }

    func allowRepositoryWindow() {
        openedDocumentDuringLaunch = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { allowRepositoryWindow() }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            openMarkdown(URL(fileURLWithPath: filename))
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openMarkdown(url)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        markdownWindows.windows.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        ThemeManager.applyInitialTheme()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let window = event.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return event
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

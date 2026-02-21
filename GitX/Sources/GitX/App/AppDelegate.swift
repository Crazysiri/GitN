import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let window = event.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return event
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

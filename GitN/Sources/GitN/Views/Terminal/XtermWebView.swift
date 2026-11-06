import AppKit
import WebKit

/// WKWebView subclass that shows a GitN terminal context menu (Copy / Paste /
/// Select All / Clear / Close) instead of the default WebKit menu. Actions are
/// executed in JS through the bridge; paste reads the system pasteboard.
final class XtermWebView: WKWebView {
    /// Hooks the owning session provides to perform each action.
    var onCopy: (() -> Void)?
    var onPaste: ((String) -> Void)?
    var onSelectAll: (() -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?
    /// Called with the raw dropped file paths (native drag handling, since
    /// WKWebView does not expose file paths to JS from a file:// page).
    var onDropPaths: (([String]) -> Void)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - File drag-and-drop (native)

    private func droppedFilePaths(from info: NSDraggingInfo) -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.map(\.path)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFilePaths(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFilePaths(from: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedFilePaths(from: sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = droppedFilePaths(from: sender)
        guard !paths.isEmpty else { return super.performDragOperation(sender) }
        window?.makeFirstResponder(self)
        onDropPaths?(paths)
        return true
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // Replace WebKit's default items with GitN's terminal menu.
        menu.removeAllItems()

        let copy = NSMenuItem(title: "Copy", action: #selector(copyAction), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)

        let paste = NSMenuItem(title: "Paste", action: #selector(pasteAction), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)

        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAllAction), keyEquivalent: "")
        selectAll.target = self
        menu.addItem(selectAll)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear", action: #selector(clearAction), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let close = NSMenuItem(title: "Close Terminal", action: #selector(closeAction), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
    }

    @objc private func copyAction() { onCopy?() }

    @objc private func pasteAction() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if !text.isEmpty { onPaste?(text) }
    }

    @objc private func selectAllAction() { onSelectAll?() }
    @objc private func clearAction() { onClear?() }
    @objc private func closeAction() { onClose?() }
}

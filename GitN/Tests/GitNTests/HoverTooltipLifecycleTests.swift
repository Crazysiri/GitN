import AppKit
import SwiftUI
import XCTest
@testable import GitN

@MainActor
final class HoverTooltipLifecycleTests: XCTestCase {
    func testControllerDoesNotCreatePanelDuringInitializationOrHide() {
        let controller = HoverTooltipPanelController()
        XCTAssertFalse(controller.hasCreatedPanel)
        controller.cancelAndHide()
        XCTAssertFalse(controller.hasCreatedPanel)
    }

    func testCanceledHoverDoesNotCreatePanel() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        window.contentView = anchor
        let controller = HoverTooltipPanelController()
        controller.scheduleShow(text: "tip", style: .standard, placement: .above, from: anchor)
        XCTAssertFalse(controller.hasCreatedPanel)
        controller.cancelAndHide()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertFalse(controller.hasCreatedPanel)
        window.contentView = nil
    }

    func testInitialWindowLayoutWithTooltipModifiersDoesNotReenterHostingLayout() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView:
            VStack {
                Text("Open repository").hoverTooltip("Open")
                Text("Clone repository").hoverTooltip("Clone")
            }.frame(width: 400, height: 200)
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.window === window)
        window.contentView = nil
    }
}

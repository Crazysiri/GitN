import AppKit
import Darwin
import XCTest
@testable import GitN

final class TerminalSessionSelectionTests: XCTestCase {
    func testAppendSelectAndCloseActiveSelectsNeighbor() {
        let ids = (0..<3).map { _ in UUID() }
        var state = TerminalSessionSelection()
        ids.forEach { state.append($0) }
        XCTAssertEqual(state.activeID, ids[2])
        state.select(ids[1])
        state.close(ids[1])
        XCTAssertEqual(state.orderedIDs, [ids[0], ids[2]])
        XCTAssertEqual(state.activeID, ids[2])
        state.close(ids[2])
        XCTAssertEqual(state.activeID, ids[0])
        state.close(ids[0])
        XCTAssertNil(state.activeID)
        XCTAssertTrue(state.orderedIDs.isEmpty)
    }

    func testNonActiveCloseAndInvalidIDsDoNotMoveSelection() {
        let ids = (0..<3).map { _ in UUID() }
        var state = TerminalSessionSelection()
        ids.forEach { state.append($0) }
        state.select(UUID())
        state.close(UUID())
        state.append(ids[0])
        XCTAssertEqual(state.orderedIDs, ids)
        XCTAssertEqual(state.activeID, ids[2])
        state.close(ids[0])
        XCTAssertEqual(state.activeID, ids[2])
    }

    func testMoveAndWrapNavigation() {
        let ids = (0..<3).map { _ in UUID() }
        var state = TerminalSessionSelection()
        ids.forEach { state.append($0) }
        state.move(ids[0], by: 1)
        state.move(ids[2], by: 1) // no-op at end
        XCTAssertEqual(state.orderedIDs, [ids[1], ids[0], ids[2]])
        state.selectAdjacent(1)
        XCTAssertEqual(state.activeID, ids[1])
        state.selectAdjacent(-1)
        XCTAssertEqual(state.activeID, ids[2])
    }

    func testCloseOthersReturnsTerminatedIDsInOrder() {
        let ids = (0..<3).map { _ in UUID() }
        var state = TerminalSessionSelection()
        ids.forEach { state.append($0) }
        XCTAssertEqual(state.closeOthers(keeping: ids[1]), [ids[0], ids[2]])
        XCTAssertEqual(state.orderedIDs, [ids[1]])
        XCTAssertEqual(state.activeID, ids[1])
    }
}

@MainActor
final class TerminalSessionLifecycleTests: XCTestCase {
    func testClosingSessionReapsInteractiveShell() async throws {
        _ = NSApplication.shared
        let store = TerminalSessionStore(repoPath: NSTemporaryDirectory(), shellPath: "/bin/sh")
        store.createSession()
        defer { store.closeAllSessions() }

        let sessionID = try XCTUnwrap(store.activeID)
        let shellPID = try XCTUnwrap(store.activeView?.process.shellPid)
        XCTAssertGreaterThan(shellPID, 0)

        store.closeSession(sessionID)
        for _ in 0..<40 where kill(shellPID, 0) == 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(kill(shellPID, 0), -1, "Closed terminal left its shell alive")
        XCTAssertEqual(errno, ESRCH)
    }
}

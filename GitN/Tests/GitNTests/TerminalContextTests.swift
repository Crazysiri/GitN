import XCTest
@testable import GitN

final class TerminalContextTests: XCTestCase {
    func testFreshCwdBecomesKnown() {
        let ctx = TerminalContext.empty.merging(observedCwd: "/Users/x/repo", observedForeground: nil)
        XCTAssertEqual(ctx.cwd, "/Users/x/repo")
        XCTAssertEqual(ctx.cwdConfidence, .known)
        XCTAssertTrue(ctx.isTrustworthyForSuggestions)
    }

    func testFailedReadKeepsCwdButMarksStale() {
        let known = TerminalContext.empty.merging(observedCwd: "/tmp/work", observedForeground: nil)
        let afterFailure = known.merging(observedCwd: nil, observedForeground: nil)
        XCTAssertEqual(afterFailure.cwd, "/tmp/work", "last known cwd retained for display")
        XCTAssertEqual(afterFailure.cwdConfidence, .stale)
        XCTAssertFalse(afterFailure.isTrustworthyForSuggestions, "stale cwd must not drive suggestions")
    }

    func testNeverKnownStaysUnknown() {
        let ctx = TerminalContext.empty.merging(observedCwd: nil, observedForeground: nil)
        XCTAssertNil(ctx.cwd)
        XCTAssertEqual(ctx.cwdConfidence, .unknown)
    }

    func testRecoveryFromStaleBackToKnown() {
        var ctx = TerminalContext.empty.merging(observedCwd: "/a", observedForeground: nil)
        ctx = ctx.merging(observedCwd: nil, observedForeground: nil)       // stale
        ctx = ctx.merging(observedCwd: "/b", observedForeground: nil)      // recovered
        XCTAssertEqual(ctx.cwd, "/b")
        XCTAssertEqual(ctx.cwdConfidence, .known)
    }

    func testForegroundClearsWhenAbsent() {
        var ctx = TerminalContext.empty.merging(observedCwd: "/a", observedForeground: "vim")
        XCTAssertEqual(ctx.foregroundProcess, "vim")
        ctx = ctx.merging(observedCwd: "/a", observedForeground: nil)
        XCTAssertNil(ctx.foregroundProcess, "a finished command must not linger as foreground")
    }

    func testEmptyObservedCwdTreatedAsFailure() {
        let known = TerminalContext.empty.merging(observedCwd: "/here", observedForeground: nil)
        let ctx = known.merging(observedCwd: "", observedForeground: nil)
        XCTAssertEqual(ctx.cwd, "/here")
        XCTAssertEqual(ctx.cwdConfidence, .stale)
    }
}

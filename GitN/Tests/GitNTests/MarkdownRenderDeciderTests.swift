import XCTest
@testable import GitN

/// Unit tests for the pure Markdown render-decision boundary (Requirements 2.2, 2.3, 2.8).
///
/// These tests exercise `MarkdownRenderDecider.decide(text:forceRich:)` directly and
/// MUST NOT instantiate any SwiftUI view bodies.
final class MarkdownRenderDeciderTests: XCTestCase {
    private let cap = MarkdownPreviewPerformance.renderCapBytes

    func testCapValueIsTheExpected256KiB() {
        XCTAssertEqual(MarkdownPreviewPerformance.renderCapBytes, 262_144)
    }

    func testTextExactlyAtCapRendersRich() {
        // ASCII "a" is a single UTF-8 byte, so count == utf8 byte length.
        let text = String(repeating: "a", count: cap)
        XCTAssertEqual(text.utf8.count, cap)
        XCTAssertEqual(MarkdownRenderDecider.decide(text: text, forceRich: false), .rich)
    }

    func testTextOneByteOverCapFallsBackToPlain() {
        let text = String(repeating: "a", count: cap + 1)
        XCTAssertEqual(text.utf8.count, cap + 1)
        XCTAssertEqual(MarkdownRenderDecider.decide(text: text, forceRich: false), .plain)
    }

    func testForceRichOnOverCapFileRendersRich() {
        let text = String(repeating: "a", count: cap + 4_096)
        XCTAssertGreaterThan(text.utf8.count, cap)
        XCTAssertEqual(MarkdownRenderDecider.decide(text: text, forceRich: true), .rich)
    }

    func testTextExceedingLegacyCharacterHeuristicButUnderCapRendersRich() {
        // Larger than richPreviewCharacterLimit (12_000) but well under the byte cap.
        let text = String(repeating: "a", count: MarkdownPreviewPerformance.richPreviewCharacterLimit + 1_000)
        XCTAssertLessThanOrEqual(text.utf8.count, cap)
        // Confirm the legacy heuristic would have suppressed rich rendering.
        XCTAssertFalse(MarkdownPreviewPerformance.shouldUseRichPreview(for: text))
        // The byte cap is the only hard gate (R2.2).
        XCTAssertEqual(MarkdownRenderDecider.decide(text: text, forceRich: false), .rich)
    }

    func testTextExceedingLegacyLineHeuristicButUnderCapRendersRich() {
        // More lines than richPreviewLineLimit (320) but under the byte cap.
        let text = Array(repeating: "- item", count: MarkdownPreviewPerformance.richPreviewLineLimit + 80)
            .joined(separator: "\n")
        XCTAssertLessThanOrEqual(text.utf8.count, cap)
        XCTAssertFalse(MarkdownPreviewPerformance.shouldUseRichPreview(for: text))
        XCTAssertEqual(MarkdownRenderDecider.decide(text: text, forceRich: false), .rich)
    }

    // MARK: - Per-file opt-in session scope (Requirements 2.4, 2.8)

    /// Helper producing a Markdown body whose UTF-8 length is strictly greater than the cap,
    /// so the default decision is `.plain` and the only way to `.rich` is the per-file opt-in.
    private func overCapText() -> String {
        let text = String(repeating: "a", count: cap + 1)
        XCTAssertGreaterThan(text.utf8.count, cap)
        return text
    }

    func testForceRichScopeStartsWithoutAnyOptIn() {
        let scope = MarkdownForceRichScope()
        XCTAssertNil(scope.optedInPath)
        XCTAssertFalse(scope.isForced(for: "README.md"))
        XCTAssertEqual(scope.decision(forPath: "README.md", text: overCapText()), .plain)
    }

    func testOptInFlipsOnlyTheTargetFileToRich() {
        var scope = MarkdownForceRichScope()
        let bigA = overCapText()

        // Over-cap file A falls back to plain by default.
        XCTAssertEqual(scope.decision(forPath: "A.md", text: bigA), .plain)

        // User clicks "Render Anyway" on A.
        scope.optIn(path: "A.md")
        XCTAssertTrue(scope.isForced(for: "A.md"))
        XCTAssertEqual(scope.decision(forPath: "A.md", text: bigA), .rich)
    }

    /// Core R2.4 / R2.8 assertion at the per-file flag layer: opting in on one over-cap file
    /// must NOT change the rendering decision for a second over-cap file in the same session.
    func testSecondOverCapFileInSameSessionStillFallsBackToPlain() {
        var scope = MarkdownForceRichScope()
        let bigA = overCapText()
        let bigB = overCapText()

        // Opt in on A.
        scope.optIn(path: "A.md")
        XCTAssertEqual(scope.decision(forPath: "A.md", text: bigA), .rich)

        // A different over-cap file opened in the same session is unaffected (no global default).
        XCTAssertFalse(scope.isForced(for: "B.md"))
        XCTAssertEqual(scope.decision(forPath: "B.md", text: bigB), .plain)
    }

    /// Switching the previewed file clears the opt-in (R2.4: revert on a later session /
    /// different file), so reopening the over-cap file shows plain again until re-opted-in.
    func testFileChangeClearsOptInSoReopenFallsBackToPlain() {
        var scope = MarkdownForceRichScope()
        let bigA = overCapText()

        scope.optIn(path: "A.md")
        XCTAssertEqual(scope.decision(forPath: "A.md", text: bigA), .rich)

        // Switch to another file, then back to A: the opt-in must not persist.
        scope.fileDidChange(to: "B.md")
        XCTAssertFalse(scope.isForced(for: "A.md"))
        scope.fileDidChange(to: "A.md")
        XCTAssertEqual(scope.decision(forPath: "A.md", text: bigA), .plain)
    }

    /// A redundant file-change notification to the already-opted-in path must not drop the
    /// opt-in (guards the view's `.onChange(of:)` reset against firing for the same file).
    func testFileChangeToSamePathKeepsOptIn() {
        var scope = MarkdownForceRichScope()
        scope.optIn(path: "A.md")
        scope.fileDidChange(to: "A.md")
        XCTAssertTrue(scope.isForced(for: "A.md"))
    }

    /// An under-cap file renders rich regardless of opt-in state, and opting in on an
    /// over-cap file never downgrades an unrelated under-cap file.
    func testUnderCapFileRendersRichIndependentOfOptIn() {
        var scope = MarkdownForceRichScope()
        let small = "# Title\n\nSmall body."

        XCTAssertEqual(scope.decision(forPath: "small.md", text: small), .rich)
        scope.optIn(path: "big.md")
        XCTAssertEqual(scope.decision(forPath: "small.md", text: small), .rich)
    }
}

import XCTest
@testable import GitN

final class MarkdownPreviewRenderingTests: XCTestCase {
    func testNormalizedFenceLanguageReturnsNilForEmptyFenceInfo() {
        XCTAssertNil(MarkdownPreviewFence.normalizedLanguage(nil))
        XCTAssertNil(MarkdownPreviewFence.normalizedLanguage(""))
        XCTAssertNil(MarkdownPreviewFence.normalizedLanguage("   \n\t"))
    }

    func testNormalizedFenceLanguageUsesFirstLowercasedToken() {
        XCTAssertEqual(MarkdownPreviewFence.normalizedLanguage("Swift"), "swift")
        XCTAssertEqual(MarkdownPreviewFence.normalizedLanguage(" json title=payload "), "json")
        XCTAssertEqual(MarkdownPreviewFence.normalizedLanguage("Mermaid {\"theme\":\"dark\"}"), "mermaid")
    }

    func testMermaidFenceDetectionHandlesWhitespaceAndCase() {
        XCTAssertTrue(MarkdownPreviewFence.isMermaid("mermaid"))
        XCTAssertTrue(MarkdownPreviewFence.isMermaid(" Mermaid "))
        XCTAssertTrue(MarkdownPreviewFence.isMermaid("MERMAID theme=neutral"))
        XCTAssertFalse(MarkdownPreviewFence.isMermaid("swift"))
        XCTAssertFalse(MarkdownPreviewFence.isMermaid(nil))
    }

    func testSyntaxHighlightingRequiresExplicitNonPlainLanguage() {
        XCTAssertFalse(MarkdownPreviewFence.shouldSyntaxHighlight(nil))
        XCTAssertFalse(MarkdownPreviewFence.shouldSyntaxHighlight(""))
        XCTAssertFalse(MarkdownPreviewFence.shouldSyntaxHighlight("plaintext"))
        XCTAssertFalse(MarkdownPreviewFence.shouldSyntaxHighlight("text"))
        XCTAssertTrue(MarkdownPreviewFence.shouldSyntaxHighlight("swift"))
        XCTAssertTrue(MarkdownPreviewFence.shouldSyntaxHighlight("json"))
    }

    func testSyntaxHighlightingFallsBackWhenResourcesAreUnavailable() {
        XCTAssertFalse(
            MarkdownCodeBlockCapabilities.shouldUseSyntaxHighlighting(
                "swift",
                isHighlightingAvailable: false
            )
        )
        XCTAssertTrue(
            MarkdownCodeBlockCapabilities.shouldUseSyntaxHighlighting(
                "swift",
                isHighlightingAvailable: true
            )
        )
    }

    func testRichMarkdownPreviewStaysEnabledForSmallDocuments() {
        let text = """
        # Title

        Small markdown body.
        """

        XCTAssertTrue(MarkdownPreviewPerformance.shouldUseRichPreview(for: text))
    }

    func testRichMarkdownPreviewFallsBackForLongDocuments() {
        let text = String(repeating: "abcd", count: 3_100)

        XCTAssertFalse(MarkdownPreviewPerformance.shouldUseRichPreview(for: text))
    }

    func testRichMarkdownPreviewFallsBackForManyLines() {
        let text = Array(repeating: "- item", count: 321).joined(separator: "\n")

        XCTAssertFalse(MarkdownPreviewPerformance.shouldUseRichPreview(for: text))
        XCTAssertEqual(MarkdownPreviewPerformance.lineCount(for: text), 321)
    }

    func testMermaidSourceHeuristicsDetectsFlowchartSyntax() {
        XCTAssertTrue(MermaidSourceHeuristics.isFlowchart("flowchart TD\nA --> B"))
        XCTAssertTrue(MermaidSourceHeuristics.isFlowchart("graph LR\nA --> B"))
        XCTAssertFalse(MermaidSourceHeuristics.isFlowchart("sequenceDiagram\nAlice->>Bob: Hi"))
    }

    func testMermaidPreprocessorAppendsLinkStyleForDottedFlowchartEdges() {
        let source = """
        flowchart TD
            A -.->|temp| B
            A --> C
        """

        let prepared = MermaidSourcePreprocessor.preparedSource(source)

        XCTAssertTrue(prepared.contains("linkStyle 0 stroke-dasharray: 6 4"),
            "dotted edges should be reinforced with explicit linkStyle")
    }
}

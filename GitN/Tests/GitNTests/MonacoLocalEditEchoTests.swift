import XCTest
@testable import GitN

final class MonacoLocalEditEchoTests: XCTestCase {
    private func preview(_ path: String, _ content: String, isDark: Bool = false) -> MonacoHostPayload {
        MonacoHostPayload(
            mode: "preview", isDark: isDark,
            preview: MonacoPreviewPayload(
                path: path, language: "markdown", content: content, isEditable: true
            ), items: []
        )
    }

    private func diff(_ path: String, _ content: String, isDark: Bool = false,
                      primaryHunkAction: String? = nil) -> MonacoHostPayload {
        MonacoHostPayload(
            mode: "diff", isDark: isDark, preview: nil,
            items: [MonacoDiffPayload(
                path: path, language: "markdown", originalText: "base",
                modifiedText: content, isEditable: true,
                primaryHunkAction: primaryHunkAction, showsDiscardAction: false,
                hunkControls: [], lineBlames: []
            )]
        )
    }

    func testPurePreviewEditEchoIsSkipped() {
        let previous = preview("a.md", "before")
        let edit = MonacoLocalEdit(path: "a.md", content: "after")
        XCTAssertTrue(MonacoLocalEditEchoPolicy.isEcho(
            preview("a.md", "after"), after: edit, comparedTo: previous
        ))
        XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(
            preview("a.md", "different"), after: edit, comparedTo: previous
        ))
    }

    func testRapidEditThenFileSwitchIsForwarded() {
        XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(
            preview("b.md", "another file"),
            after: MonacoLocalEdit(path: "a.md", content: "after"),
            comparedTo: preview("a.md", "before")
        ))
    }

    func testThemeChangeIsForwardedEvenWhenContentMatchesLocalEdit() {
        XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(
            preview("a.md", "after", isDark: true),
            after: MonacoLocalEdit(path: "a.md", content: "after"),
            comparedTo: preview("a.md", "before")
        ))
    }

    func testDiffMetadataChangeIsForwardedEvenWhenContentMatchesLocalEdit() {
        let edit = MonacoLocalEdit(path: "a.md", content: "after")
        XCTAssertTrue(MonacoLocalEditEchoPolicy.isEcho(
            diff("a.md", "after"), after: edit, comparedTo: diff("a.md", "before")
        ))
        XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(
            diff("a.md", "after", primaryHunkAction: "stage"),
            after: edit, comparedTo: diff("a.md", "before")
        ))
        XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(
            diff("b.md", "after"), after: edit, comparedTo: diff("a.md", "before")
        ))
    }
    func testLayoutSwitchIsNotSwallowedAsLocalEditEcho() {
        let edit = MonacoLocalEdit(path: "a.md", content: "after")
        for mode in DiffDisplayMode.allCases {
            var previous = diff("a.md", "before")
            previous.diffDisplay = mode.rawValue
            var next = diff("a.md", "after")
            next.diffDisplay = mode.rawValue
            XCTAssertTrue(MonacoLocalEditEchoPolicy.isEcho(next, after: edit, comparedTo: previous))
            for other in DiffDisplayMode.allCases where other != mode {
                next.diffDisplay = other.rawValue
                XCTAssertFalse(MonacoLocalEditEchoPolicy.isEcho(next, after: edit, comparedTo: previous))
            }
        }
    }

}

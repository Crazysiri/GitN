import XCTest
@testable import GitN

final class DiffParserPathTests: XCTestCase {
    func testExtractsHeaderPathsForRegularDiff() {
        let diff = DiffParserEngine.parse(
            [
                "diff --git a/Sources/App.swift b/Sources/App.swift",
                "index 1111111..2222222 100644",
                "--- a/Sources/App.swift",
                "+++ b/Sources/App.swift",
                "@@ -1 +1 @@",
                "-old",
                "+new",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(diff.oldPath, "Sources/App.swift")
        XCTAssertEqual(diff.newPath, "Sources/App.swift")
    }

    func testExtractsHeaderPathsForRenameDiff() {
        let diff = DiffParserEngine.parse(
            [
                "diff --git a/OldName.swift b/NewName.swift",
                "similarity index 80%",
                "rename from OldName.swift",
                "rename to NewName.swift",
                "--- a/OldName.swift",
                "+++ b/NewName.swift",
                "@@ -1 +1 @@",
                "-old",
                "+new",
            ].joined(separator: "\n")
        )

        XCTAssertEqual(diff.oldPath, "OldName.swift")
        XCTAssertEqual(diff.newPath, "NewName.swift")
    }

    func testTreatsDevNullHeaderAsMissingPath() {
        let diff = DiffParserEngine.parse(
            [
                "diff --git a/NewFile.swift b/NewFile.swift",
                "new file mode 100644",
                "--- /dev/null",
                "+++ b/NewFile.swift",
                "@@ -0,0 +1 @@",
                "+new",
            ].joined(separator: "\n")
        )

        XCTAssertNil(diff.oldPath)
        XCTAssertEqual(diff.newPath, "NewFile.swift")
    }
}

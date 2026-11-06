import XCTest
@testable import GitN

final class SuggestionEngineTests: XCTestCase {
    func testCommandWordSuggestsKnownCommands() {
        let plan = SuggestionEngine.plan(line: "gi", cursor: 2)
        XCTAssertEqual(plan.dynamicNeed, .none)
        XCTAssertTrue(plan.staticSuggestions.contains { $0.insertText == "git" })
        XCTAssertFalse(plan.staticSuggestions.contains { $0.insertText == "npm" })
    }

    func testGitSubcommandSuggestions() {
        let plan = SuggestionEngine.plan(line: "git che", cursor: 7)
        XCTAssertEqual(plan.dynamicNeed, .none)
        XCTAssertTrue(plan.staticSuggestions.contains { $0.insertText == "checkout" })
        XCTAssertEqual(plan.prefix, "che")
    }

    func testGitCheckoutNeedsBranches() {
        let plan = SuggestionEngine.plan(line: "git checkout ma", cursor: 15)
        XCTAssertEqual(plan.dynamicNeed, .gitBranches)
        XCTAssertEqual(plan.prefix, "ma")
    }

    func testGitAddNeedsFiles() {
        let plan = SuggestionEngine.plan(line: "git add src", cursor: 11)
        XCTAssertEqual(plan.dynamicNeed, .gitFiles)
    }

    func testCdNeedsDirectories() {
        let plan = SuggestionEngine.plan(line: "cd sr", cursor: 5)
        XCTAssertEqual(plan.dynamicNeed, .directories)
        XCTAssertEqual(plan.prefix, "sr")
    }

    func testNpmRunNeedsScripts() {
        let plan = SuggestionEngine.plan(line: "npm run bu", cursor: 10)
        XCTAssertEqual(plan.dynamicNeed, .packageScripts)
    }

    func testOptionPrefixSuppressesDynamic() {
        let plan = SuggestionEngine.plan(line: "git checkout -", cursor: 14)
        XCTAssertEqual(plan.dynamicNeed, .none, "an option token must not fetch branches")
    }

    func testReplacementRangeCoversActiveToken() {
        let line = "git checkout ma"
        let plan = SuggestionEngine.plan(line: line, cursor: line.count)
        XCTAssertEqual(plan.replacementRange, 13..<15)
    }

    func testEscapingQuotesPathsWithSpaces() {
        XCTAssertEqual(ShellWordEscaping.escape("my file"), "'my file'")
        XCTAssertEqual(ShellWordEscaping.escape("simple"), "simple")
        XCTAssertEqual(ShellWordEscaping.escape("a'b"), "'a'\\''b'")
    }
}

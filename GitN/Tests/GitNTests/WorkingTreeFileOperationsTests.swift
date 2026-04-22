import XCTest
@testable import GitN

final class WorkingTreeFileOperationsTests: XCTestCase {
    func testCreateFileAndFolderInNestedPaths() throws {
        let repo = try TemporaryGitRepository()
        let operations = WorkingTreeFileOperations(repoPath: repo.path)

        let folderPath = try operations.createFolder(named: "Sources")
        let filePath = try operations.createFile(named: "App.swift", in: folderPath)

        XCTAssertEqual(folderPath, "Sources")
        XCTAssertEqual(filePath, "Sources/App.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(filePath).path))
    }

    func testRenameFolderPreservesNestedContents() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("docs/specs/notes.md", contents: "hello\n")
        let operations = WorkingTreeFileOperations(repoPath: repo.path)

        let renamedPath = try operations.renameItem(at: "docs", to: "guides")

        XCTAssertEqual(renamedPath, "guides")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("guides/specs/notes.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("docs").path))
    }

    func testDeleteRemovesNonEmptyFolder() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tmp/cache/file.txt", contents: "x\n")
        let operations = WorkingTreeFileOperations(repoPath: repo.path)

        try operations.deleteItem(at: "tmp")

        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("tmp").path))
    }

    func testValidatedInlineNameRejectsEmptyAndSeparators() {
        XCTAssertThrowsError(try WorkingTreeFileOperations.validatedInlineName("   "))
        XCTAssertThrowsError(try WorkingTreeFileOperations.validatedInlineName("bad/name"))
        XCTAssertThrowsError(try WorkingTreeFileOperations.validatedInlineName("bad:name"))
    }
}

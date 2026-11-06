import Foundation
import XCTest
@testable import GitN

final class GitCLIPipeSafetyTests: XCTestCase {
    func testLargeOutputOnBothPipesAndLargeInputDoNotDeadlock() async throws {
        let repo = try TemporaryGitRepository()
        let alias = "!sh -c 'head -c 1048576 /dev/zero 1>&2; head -c 1048576 /dev/zero; cat >/dev/null; printf done'"
        try repo.run(["config", "alias.pipe-stress", alias])
        let cli = GitCLI(repoPath: repo.path)
        let input = String(repeating: "x", count: 1048576)

        let captured = try await cli.capture(["pipe-stress"], input: input)
        XCTAssertEqual(captured.exitCode, 0)
        XCTAssertEqual(captured.stderr.count, 1048576)
        XCTAssertEqual(captured.stdout.count, 1048580)
        XCTAssertEqual(String(decoding: captured.stdout.suffix(4), as: UTF8.self), "done")

        let output = try await cli.output(["pipe-stress"], input: input)
        XCTAssertEqual(output.utf8.count, 1048580)
    }

    func testRawBlobOutputRetainsNonUTF8Bytes() async throws {
        let repo = try TemporaryGitRepository()
        let bytes = try XCTUnwrap("你好\n".data(using: .utf16))
        try bytes.write(to: repo.url.appendingPathComponent("编码.md"))
        try repo.commitAll(message: "utf16 document")

        let cli = GitCLI(repoPath: repo.path)
        let result = try await cli.outputData(["show", "HEAD:编码.md"])
        XCTAssertEqual(result, bytes)
        do {
            _ = try await cli.output(["show", "HEAD:编码.md"])
            XCTFail("Text convenience output must not turn a binary blob into an empty file")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("non-UTF-8"))
        }
    }

    func testCaptureKeepsExitCodeAndDiagnostics() async throws {
        let repo = try TemporaryGitRepository()
        let cli = GitCLI(repoPath: repo.path)
        let captured = try await cli.capture(["show", "does-not-exist"])
        XCTAssertNotEqual(captured.exitCode, 0)
        XCTAssertFalse(captured.stderr.isEmpty)
        do {
            _ = try await cli.output(["show", "does-not-exist"])
            XCTFail("Expected a Git failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testCloneFromNonRepositoryParentKeepsCommittedContent() async throws {
        let source = try TemporaryGitRepository()
        try "cloned content\n".write(
            to: source.url.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try source.commitAll(message: "clone source")
        let destination = source.url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }

        let cli = GitCLI(repoPath: source.url.deletingLastPathComponent().path)
        try await cli.run(["clone", "--", source.path, destination.path])
        let content = try String(contentsOf: destination.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertEqual(content, "cloned content\n")
    }
}

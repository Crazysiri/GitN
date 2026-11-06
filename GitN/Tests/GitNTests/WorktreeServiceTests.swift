import Foundation
import XCTest
@testable import GitN

final class WorktreeServiceTests: XCTestCase {
    func testPorcelainParserPreservesPathsAndState() throws {
        let path = "/tmp/GitN worktree\nwith newline"
        let fixture = [
            "worktree /tmp/main", "HEAD abc123", "branch refs/heads/main", "",
            "worktree \(path)", "HEAD def456", "branch refs/heads/feature/deep", "locked maintenance", "",
            "worktree /tmp/missing", "HEAD def456", "detached", "prunable gitdir missing", "", ""
        ].joined(separator: "\0")

        let worktrees = try WorktreePorcelainParser.parse(Data(fixture.utf8))
        XCTAssertEqual(worktrees.count, 3)
        XCTAssertEqual(worktrees[0].branchName, "main")
        XCTAssertTrue(worktrees[0].isMain)
        XCTAssertEqual(worktrees[1].path, path)
        XCTAssertEqual(worktrees[1].branchName, "feature/deep")
        XCTAssertEqual(worktrees[1].lockedReason, "maintenance")
        XCTAssertTrue(worktrees[2].isDetached)
        XCTAssertTrue(worktrees[2].isPrunable)
    }

    func testPorcelainParserRejectsMalformedRecord() {
        XCTAssertThrowsError(try WorktreePorcelainParser.parse(Data("HEAD abc\0\0".utf8)))
    }

    func testAddListAndRemoveRealWorktree() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "hello\n")
        try repo.commitAll(message: "initial")
        let service = WorktreeService(repoPath: repo.path)
        let linked = repo.url.deletingLastPathComponent()
            .appendingPathComponent("GitN linked \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: linked) }

        try await service.add(path: linked.path, branch: "feature/test", createBranch: true)
        var worktrees = try await service.list()
        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(WorktreeService.canonicalPath(worktrees[1].path), WorktreeService.canonicalPath(linked.path))
        XCTAssertEqual(worktrees[1].branchName, "feature/test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: linked.appendingPathComponent("README.md").path))

        try await service.remove(worktrees[1])
        worktrees = try await service.list()
        XCTAssertEqual(worktrees.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
        XCTAssertNotNil(try? repo.run(["show-ref", "--verify", "refs/heads/feature/test"]))
    }

    func testDirtyAndMainWorktreesCannotBeRemoved() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "hello\n")
        try repo.commitAll(message: "initial")
        let service = WorktreeService(repoPath: repo.path)
        let linked = repo.url.deletingLastPathComponent()
            .appendingPathComponent("GitN dirty \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: linked) }

        try await service.add(path: linked.path, branch: "feature/dirty", createBranch: true)
        let worktrees = try await service.list()
        await XCTAssertThrowsErrorAsync(try await service.remove(worktrees[0]))
        let linkedService = WorktreeService(repoPath: linked.path)
        await XCTAssertThrowsErrorAsync(try await linkedService.remove(worktrees[1]))

        try "change\n".write(to: linked.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        await XCTAssertThrowsErrorAsync(try await service.remove(worktrees[1]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linked.path))
    }

    func testExistingBranchAndCheckedOutBranchSafety() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "hello\n")
        try repo.commitAll(message: "initial")
        try repo.run(["branch", "feature/existing"])
        let service = WorktreeService(repoPath: repo.path)
        let linked = repo.url.deletingLastPathComponent()
            .appendingPathComponent("GitN existing \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: linked) }

        await XCTAssertThrowsErrorAsync(try await service.add(
            path: linked.path, branch: "main", createBranch: false
        ))
        try await service.add(path: linked.path, branch: "feature/existing", createBranch: false)
        let listed = try await service.list()
        XCTAssertEqual(listed.last?.branchName, "feature/existing")
        await XCTAssertThrowsErrorAsync(try await service.add(
            path: linked.path + "-duplicate", branch: "feature/existing", createBranch: false
        ))
        try await service.remove(try XCTUnwrap(listed.last))
    }

    @MainActor
    func testViewModelKeepsAnOpenWorktree() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "hello\n")
        try repo.commitAll(message: "initial")
        let viewModel = RepoViewModel(path: repo.path, name: "test")
        let linked = repo.url.deletingLastPathComponent()
            .appendingPathComponent("GitN open \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: linked) }

        let created = await viewModel.performCreateWorktree(
            path: linked.path, branch: "feature/open", createBranch: true
        )
        XCTAssertNotNil(created)
        let worktree = try XCTUnwrap(viewModel.worktrees.first { !$0.isMain })
        let removed = await viewModel.performRemoveWorktree(
            worktree, openPaths: [WorktreeService.canonicalPath(linked.path)]
        )
        XCTAssertFalse(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linked.path))
        let removedAfterClosing = await viewModel.performRemoveWorktree(worktree, openPaths: [])
        XCTAssertTrue(removedAfterClosing)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch { }
}

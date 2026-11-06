import XCTest
@testable import GitN

final class RepositoryFileWatcherTests: XCTestCase {
    func testStandardRepositoryMetadataAndTrackedBuildDirectory() throws {
        let repo = try TemporaryGitRepository()
        let paths = GitRepositoryMetadataPaths(repoPath: repo.path)
        let gitDir = repo.url.appendingPathComponent(".git").path

        XCTAssertEqual(paths.gitDirPath, gitDir)
        XCTAssertEqual(paths.commonDirPath, gitDir)
        XCTAssertEqual(paths.watchPaths.count, 2)
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: gitDir + "/index", metadataPaths: paths),
            [.index]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: gitDir + "/refs/heads/main", metadataPaths: paths),
            [.refs]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: gitDir + "/worktrees/linked/HEAD", metadataPaths: paths),
            [.worktrees]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: repo.path + "/dist/tracked.js", metadataPaths: paths),
            [.workingDirectory]
        )
        XCTAssertTrue(
            RepositoryFileWatcher.changeKinds(for: gitDir + "/objects/aa/blob", metadataPaths: paths).isEmpty
        )
        XCTAssertTrue(
            RepositoryFileWatcher.changeKinds(for: repo.path + "-sibling/file", metadataPaths: paths).isEmpty
        )
    }

    func testLinkedWorktreeResolvesPerWorktreeIndexAndSharedRefs() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("initial.txt", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let worktreeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitN-worktree-\(UUID().uuidString)")
        try repo.run(["worktree", "add", "--detach", worktreeURL.path])
        defer { _ = try? repo.run(["worktree", "remove", "--force", worktreeURL.path]) }

        let paths = GitRepositoryMetadataPaths(repoPath: worktreeURL.path)
        XCTAssertTrue(paths.gitDirPath.hasPrefix(repo.path + "/.git/worktrees/"))
        XCTAssertEqual(paths.commonDirPath, repo.path + "/.git")
        XCTAssertEqual(paths.watchPaths.count, 3)
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: paths.gitDirPath + "/index", metadataPaths: paths),
            [.index]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: paths.gitDirPath + "/HEAD", metadataPaths: paths),
            [.head]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: paths.commonDirPath + "/packed-refs", metadataPaths: paths),
            [.refs]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: paths.commonDirPath + "/worktrees/sibling/HEAD", metadataPaths: paths),
            [.worktrees]
        )
        XCTAssertEqual(
            RepositoryFileWatcher.changeKinds(for: worktreeURL.path + "/.git", metadataPaths: paths),
            [.head, .refs, .index]
        )
        XCTAssertTrue(
            RepositoryFileWatcher.changeKinds(for: paths.commonDirPath + "/objects/aa/blob", metadataPaths: paths).isEmpty
        )
    }
}

import XCTest
@testable import GitN

final class RepoReflogLoaderTests: XCTestCase {
    func testLoadBuildsRecoveredCommitSnapshotForLostCommit() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let initialHash = try repo.commitAll(message: "initial")

        try repo.appendFile("tracked.txt", contents: "two\n")
        let lostHash = try repo.commitAll(message: "lost")
        try repo.run(["reset", "--hard", initialHash])

        let loader = RepoReflogLoader(git: GitService(repoPath: repo.path))
        let snapshot = try await loader.load(refName: "HEAD")

        XCTAssertTrue(snapshot.entries.contains(where: { $0.kind == .commit }))
        XCTAssertTrue(snapshot.entriesByCommitHash.keys.contains(lostHash))
        XCTAssertTrue(snapshot.recoveredCommits.contains(where: { $0.hash == lostHash }))
        XCTAssertTrue(snapshot.recoveryEntriesByCommitHash.keys.contains(lostHash))
    }

    func testLoadKeepsRecoveredCollectionsEmptyWhenAllReflogCommitsReachable() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let headHash = try repo.commitAll(message: "initial")

        let loader = RepoReflogLoader(git: GitService(repoPath: repo.path))
        let snapshot = try await loader.load(refName: "HEAD")

        XCTAssertFalse(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.entriesByCommitHash.keys.contains(headHash))
        XCTAssertTrue(snapshot.recoveredCommits.isEmpty)
        XCTAssertTrue(snapshot.recoveryEntriesByCommitHash.isEmpty)
    }
}

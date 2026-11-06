import Foundation
import XCTest
@testable import GitN

@MainActor
final class RemoteTagPrunerTests: XCTestCase {
    func testSyncPreservesLocalOnlyRefsAndPrunesOnlyTrackedRemoteRefs() async throws {
        let fixture = try makeFixture()
        let repo = fixture.repo
        let service = GitService(repoPath: repo.path)
        let pruner = RemoteTagPruner(repoPath: repo.path, defaults: fixture.defaults)

        try repo.run(["tag", "local-only"])
        try repo.run(["branch", "local-only-branch"])
        try repo.run(["branch", "remote-removed"])
        try repo.run(["push", "origin", "remote-removed"])
        try repo.run(["fetch", "--no-tags", "origin"])
        try repo.run(["push", "origin", "--delete", "remote-removed"])

        let beforeFirstFetch = try await pruner.localTagOIDs()
        try await service.fetchWithPrune()
        let firstPruned = try await pruner.pruneAfterSuccessfulFetch(
            remotes: [fixture.remote], localTagsBeforeFetch: beforeFirstFetch
        )
        let firstTags = try await pruner.localTagOIDs()
        XCTAssertEqual(firstPruned, 0)
        XCTAssertNotNil(firstTags["local-only"])
        XCTAssertNotNil(firstTags["remote-owned"])
        XCTAssertNotNil(try? repo.run(["show-ref", "--verify", "refs/heads/local-only-branch"]))
        XCTAssertNil(try? repo.run(["show-ref", "--verify", "refs/remotes/origin/remote-removed"]))

        try repo.run(["push", "origin", ":refs/tags/remote-owned"])
        let beforeSecondFetch = try await pruner.localTagOIDs()
        try await service.fetchWithPrune()
        let secondPruned = try await pruner.pruneAfterSuccessfulFetch(
            remotes: [fixture.remote], localTagsBeforeFetch: beforeSecondFetch
        )
        let secondTags = try await pruner.localTagOIDs()
        XCTAssertEqual(secondPruned, 1)
        XCTAssertNil(secondTags["remote-owned"])
        XCTAssertNotNil(secondTags["local-only"])
        XCTAssertNotNil(try? repo.run(["show-ref", "--verify", "refs/heads/local-only-branch"]))
    }

    func testMovedFetchedTagAndPreexistingTagArePreserved() async throws {
        let fixture = try makeFixture()
        let repo = fixture.repo
        let service = GitService(repoPath: repo.path)
        let pruner = RemoteTagPruner(repoPath: repo.path, defaults: fixture.defaults)

        try repo.run(["tag", "preexisting"])
        let beforeFirstFetch = try await pruner.localTagOIDs()
        try await service.fetchWithPrune()
        _ = try await pruner.pruneAfterSuccessfulFetch(
            remotes: [fixture.remote], localTagsBeforeFetch: beforeFirstFetch
        )

        try repo.writeFile("second.txt", contents: "second\n")
        try repo.commitAll(message: "second")
        try repo.run(["tag", "-f", "remote-owned"])
        try repo.run(["push", "origin", ":refs/tags/remote-owned"])
        let beforeSecondFetch = try await pruner.localTagOIDs()
        try await service.fetchWithPrune()
        let pruned = try await pruner.pruneAfterSuccessfulFetch(
            remotes: [fixture.remote], localTagsBeforeFetch: beforeSecondFetch
        )
        let tags = try await pruner.localTagOIDs()
        XCTAssertEqual(pruned, 0)
        XCTAssertNotNil(tags["remote-owned"])
        XCTAssertNotNil(tags["preexisting"])
    }

    func testRemoteQueryFailureLeavesFetchedTagUntouched() async throws {
        let fixture = try makeFixture()
        let repo = fixture.repo
        let service = GitService(repoPath: repo.path)
        let pruner = RemoteTagPruner(repoPath: repo.path, defaults: fixture.defaults)

        let beforeFirstFetch = try await pruner.localTagOIDs()
        try await service.fetchWithPrune()
        _ = try await pruner.pruneAfterSuccessfulFetch(
            remotes: [fixture.remote], localTagsBeforeFetch: beforeFirstFetch
        )
        try repo.run(["remote", "set-url", "origin", repo.url.appendingPathComponent("missing.git").path])
        let beforeSecondFetch = try await pruner.localTagOIDs()
        do {
            _ = try await pruner.pruneAfterSuccessfulFetch(
                remotes: [fixture.remote], localTagsBeforeFetch: beforeSecondFetch
            )
            XCTFail("Expected remote tag query to fail")
        } catch {
            let tags = try await pruner.localTagOIDs()
            XCTAssertNotNil(tags["remote-owned"])
        }
    }

    private func makeFixture() throws -> (repo: TemporaryGitRepository, remote: RemoteInfo, defaults: UserDefaults) {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("README.md", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitNRemote-\(UUID().uuidString).git")
        addTeardownBlock { try? FileManager.default.removeItem(at: bareURL) }
        try repo.run(["init", "--bare", bareURL.path])
        try repo.run(["remote", "add", "origin", bareURL.path])
        try repo.run(["push", "origin", "main"])
        try repo.run(["tag", "remote-owned"])
        try repo.run(["push", "origin", "refs/tags/remote-owned"])
        try repo.run(["tag", "--delete", "remote-owned"])
        let suiteName = "GitNTests.RemoteTagPruner.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return (repo, RemoteInfo(name: "origin", url: bareURL.path), defaults)
    }
}

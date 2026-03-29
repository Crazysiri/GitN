import XCTest
@testable import GitN

@MainActor
final class RepoViewModelReflogNavigationTests: XCTestCase {
    func testSelectRecoveredCommitKeepsScrollTargetForRecoveredCommit() async {
        let viewModel = RepoViewModel(path: "/tmp/repo", name: "repo")
        let recoveredCommit = CommitInfo(
            hash: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
            shortHash: "deadbee",
            parentHashes: ["cafebabecafebabecafebabecafebabecafebabe"],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Recovered commit",
            refs: []
        )

        await viewModel.selectRecoveredCommit(recoveredCommit)

        XCTAssertEqual(viewModel.selectedCommit?.hash, recoveredCommit.hash)
        XCTAssertEqual(viewModel.scrollToCommitHash, recoveredCommit.hash)
    }
}

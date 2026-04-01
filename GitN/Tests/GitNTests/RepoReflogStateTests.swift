import XCTest
@testable import GitN

final class RepoReflogStateTests: XCTestCase {
    func testSourceOptionsAndCanNavigateReflectBranchAndLoadState() {
        let existing = CommitInfo(
            hash: String(repeating: "a", count: 40),
            shortHash: "aaaaaaa",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Existing",
            refs: []
        )
        let recovered = CommitInfo(
            hash: String(repeating: "b", count: 40),
            shortHash: "bbbbbbb",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Recovered",
            refs: []
        )
        let state = RepoReflogState(
            currentBranch: "feature/demo",
            isDetachedHead: false,
            baseCommits: [existing],
            recoveredCommits: [recovered],
            visibleEntriesByCommitHash: [:],
            recoveryEntriesByCommitHash: [:],
            showReflogOverlay: true,
            allCommitsLoaded: true
        )

        XCTAssertEqual(
            state.sourceOptions,
            [
                ReflogSourceOption(refName: "HEAD", title: "HEAD"),
                ReflogSourceOption(refName: "refs/heads/feature/demo", title: "feature/demo"),
            ]
        )
        XCTAssertTrue(state.canNavigateToCommit(hash: String(existing.hash.prefix(8))))
        XCTAssertTrue(state.canNavigateToCommit(hash: String(recovered.hash.prefix(8))))
        XCTAssertFalse(state.canNavigateToCommit(hash: String(repeating: "c", count: 40)))
    }

    func testMergedAndBadgeEntriesDeduplicateByIdentifierAndKind() {
        let hash = String(repeating: "d", count: 40)
        let checkout = ReflogEntryInfo(
            refName: "HEAD",
            index: 0,
            oldOID: nil,
            newOID: hash,
            message: "checkout",
            kind: .checkout,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 10:00:00 +0000"
        )
        let duplicateCheckout = ReflogEntryInfo(
            refName: "HEAD",
            index: 0,
            oldOID: nil,
            newOID: hash,
            message: "checkout",
            kind: .checkout,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 10:00:00 +0000"
        )
        let commit = ReflogEntryInfo(
            refName: "HEAD",
            index: 1,
            oldOID: nil,
            newOID: hash,
            message: "commit",
            kind: .commit,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 09:00:00 +0000"
        )
        let state = RepoReflogState(
            currentBranch: "",
            isDetachedHead: false,
            baseCommits: [],
            recoveredCommits: [],
            visibleEntriesByCommitHash: [hash: [commit]],
            recoveryEntriesByCommitHash: [hash: [duplicateCheckout, checkout]],
            showReflogOverlay: true,
            allCommitsLoaded: false
        )

        XCTAssertEqual(state.mergedEntries(for: hash), [checkout, commit])
        XCTAssertEqual(state.badgeEntries(for: hash).map(\.kind), [.checkout, .commit])
    }

    func testDisplayCommitsPinsUncommittedAndAnchorsRecoveredChains() {
        let anchor = CommitInfo(
            hash: String(repeating: "1", count: 40),
            shortHash: "1111111",
            parentHashes: [String(repeating: "0", count: 40)],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "anchor",
            refs: []
        )
        let recoveredBase = CommitInfo(
            hash: String(repeating: "2", count: 40),
            shortHash: "2222222",
            parentHashes: [anchor.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "recovered base",
            refs: []
        )
        let recoveredTip = CommitInfo(
            hash: String(repeating: "3", count: 40),
            shortHash: "3333333",
            parentHashes: [recoveredBase.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "recovered tip",
            refs: []
        )
        let state = RepoReflogState(
            currentBranch: "main",
            isDetachedHead: false,
            baseCommits: [
                CommitInfo.uncommittedEntry(parentHash: anchor.hash, stagedCount: 1, unstagedCount: 0),
                anchor,
            ],
            recoveredCommits: [recoveredBase, recoveredTip],
            visibleEntriesByCommitHash: [:],
            recoveryEntriesByCommitHash: [
                recoveredBase.hash: [
                    ReflogEntryInfo(
                        refName: "HEAD",
                        index: 2,
                        oldOID: nil,
                        newOID: recoveredBase.hash,
                        message: "recover base",
                        kind: .commit,
                        committerName: "Test",
                        committerEmail: "test@example.com",
                        date: "2026-03-29 09:00:00 +0000"
                    )
                ],
                recoveredTip.hash: [
                    ReflogEntryInfo(
                        refName: "HEAD",
                        index: 1,
                        oldOID: nil,
                        newOID: recoveredTip.hash,
                        message: "recover tip",
                        kind: .commit,
                        committerName: "Test",
                        committerEmail: "test@example.com",
                        date: "2026-03-29 10:00:00 +0000"
                    )
                ],
            ],
            showReflogOverlay: true,
            allCommitsLoaded: false
        )

        XCTAssertEqual(
            state.displayCommits.map(\.hash),
            [CommitInfo.uncommittedHash, recoveredTip.hash, recoveredBase.hash, anchor.hash]
        )
        XCTAssertEqual(state.displayCommit(matching: String(recoveredTip.hash.prefix(10)))?.hash, recoveredTip.hash)
        XCTAssertTrue(state.isRecoveredCommit(recoveredTip))
    }

    func testDisplayCommitsReturnsBaseCommitsWhenReflogOverlayIsDisabled() {
        let existing = CommitInfo(
            hash: String(repeating: "a", count: 40),
            shortHash: "aaaaaaa",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Existing",
            refs: []
        )
        let recovered = CommitInfo(
            hash: String(repeating: "b", count: 40),
            shortHash: "bbbbbbb",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Recovered",
            refs: []
        )
        let state = RepoReflogState(
            currentBranch: "main",
            isDetachedHead: false,
            baseCommits: [existing],
            recoveredCommits: [recovered],
            visibleEntriesByCommitHash: [:],
            recoveryEntriesByCommitHash: [:],
            showReflogOverlay: false,
            allCommitsLoaded: true
        )

        XCTAssertEqual(state.displayCommits.map(\.hash), [existing.hash])
    }

    func testSourceOptionsOmitSyntheticBranchOptionWhileHeadIsDetached() {
        let state = RepoReflogState(
            currentBranch: "abc1234",
            isDetachedHead: true,
            baseCommits: [],
            recoveredCommits: [],
            visibleEntriesByCommitHash: [:],
            recoveryEntriesByCommitHash: [:],
            showReflogOverlay: false,
            allCommitsLoaded: true
        )

        XCTAssertEqual(
            state.sourceOptions,
            [ReflogSourceOption(refName: "HEAD", title: "HEAD")]
        )
    }
}

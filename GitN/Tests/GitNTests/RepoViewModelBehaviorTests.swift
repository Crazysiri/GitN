import XCTest
@testable import GitN

@MainActor
final class RepoViewModelBehaviorTests: XCTestCase {
    private let onePixelPNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN6kAAAAASUVORK5CYII=")!

    func testReflogEntriesMergeVisibleAndRecoveredEntriesWithoutDuplicates() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let hash = String(repeating: "a", count: 40)

        let newer = ReflogEntryInfo(
            refName: "HEAD",
            index: 0,
            oldOID: String(repeating: "b", count: 40),
            newOID: hash,
            message: "checkout: moving from main to topic",
            kind: .checkout,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 10:00:00 +0000"
        )
        let duplicate = ReflogEntryInfo(
            refName: "HEAD",
            index: 0,
            oldOID: String(repeating: "b", count: 40),
            newOID: hash,
            message: "checkout: moving from main to topic",
            kind: .checkout,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 10:00:00 +0000"
        )
        let older = ReflogEntryInfo(
            refName: "HEAD",
            index: 1,
            oldOID: String(repeating: "c", count: 40),
            newOID: hash,
            message: "commit: recovered work",
            kind: .commit,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 09:00:00 +0000"
        )

        viewModel.reflogEntriesByCommitHash = [hash: [older]]
        viewModel.reflogRecoveryEntriesByCommitHash = [hash: [duplicate, newer]]

        XCTAssertEqual(viewModel.reflogEntries(for: hash), [newer, older])
    }

    func testReflogBadgeEntriesDeduplicateKindsAcrossMergedEntries() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
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
        let commitA = ReflogEntryInfo(
            refName: "HEAD",
            index: 1,
            oldOID: nil,
            newOID: hash,
            message: "commit a",
            kind: .commit,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 09:00:00 +0000"
        )
        let commitB = ReflogEntryInfo(
            refName: "HEAD",
            index: 2,
            oldOID: nil,
            newOID: hash,
            message: "commit b",
            kind: .commit,
            committerName: "Test",
            committerEmail: "test@example.com",
            date: "2026-03-29 08:00:00 +0000"
        )

        viewModel.reflogEntriesByCommitHash = [hash: [checkout, commitA, commitB]]

        XCTAssertEqual(viewModel.reflogBadgeEntries(for: hash).map(\.kind), [.checkout, .commit])
    }

    func testGraphDisplayCommitsPinsUncommittedEntryAndAnchorsRecoveredChain() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")

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
        let older = CommitInfo(
            hash: String(repeating: "2", count: 40),
            shortHash: "2222222",
            parentHashes: [anchor.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-28",
            message: "older",
            refs: []
        )
        let recoveredBase = CommitInfo(
            hash: String(repeating: "3", count: 40),
            shortHash: "3333333",
            parentHashes: [anchor.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "recovered base",
            refs: []
        )
        let recoveredTip = CommitInfo(
            hash: String(repeating: "4", count: 40),
            shortHash: "4444444",
            parentHashes: [recoveredBase.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "recovered tip",
            refs: []
        )

        viewModel.commits = [
            CommitInfo.uncommittedEntry(parentHash: anchor.hash, stagedCount: 1, unstagedCount: 0),
            anchor,
            older,
        ]
        viewModel.reflogRecoveredCommits = [recoveredBase, recoveredTip]
        viewModel.reflogRecoveryEntriesByCommitHash = [
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
        ]
        viewModel.showReflogOverlay = true

        XCTAssertEqual(
            viewModel.graphDisplayCommits.map(\.hash),
            [
                CommitInfo.uncommittedHash,
                recoveredTip.hash,
                recoveredBase.hash,
                anchor.hash,
                older.hash,
            ]
        )
    }

    func testGraphDisplayModeCurrentFiltersToCurrentBranchHashesAndKeepsUncommitted() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let visible = CommitInfo(
            hash: String(repeating: "1", count: 40),
            shortHash: "1111111",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "visible",
            refs: []
        )
        let hidden = CommitInfo(
            hash: String(repeating: "2", count: 40),
            shortHash: "2222222",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "hidden",
            refs: []
        )

        viewModel.commits = [
            CommitInfo.uncommittedEntry(parentHash: visible.hash, stagedCount: 1, unstagedCount: 0),
            visible,
            hidden,
        ]
        viewModel.setCurrentBranchHashesForTesting([visible.hash])
        viewModel.graphDisplayMode = .current

        XCTAssertEqual(
            viewModel.graphDisplayCommits.map(\.hash),
            [CommitInfo.uncommittedHash, visible.hash]
        )
    }

    func testSaveConflictResolutionWarnsWhenNoHunksSelected() async {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha",
                "<<<<<<< Current",
                "current-1",
                "||||||| Base",
                "base-1",
                "=======",
                "incoming-1",
                ">>>>>>> Incoming",
                "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "omega"],
            oursLines: ["alpha", "current-1", "omega"],
            theirsLines: ["alpha", "incoming-1", "omega"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        viewModel.conflictMergeFile = ConflictFile(path: "file.txt", conflictCount: 1)
        let document = ConflictEditorDocument(sides: sides)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.conflictOutputLines = document.outputLines
        viewModel.showConflictMergeView = true

        await viewModel.saveConflictResolution()

        XCTAssertEqual(viewModel.toastMessage?.title, "No Hunks Selected")
        XCTAssertEqual(viewModel.toastMessage?.style, .warning)
        XCTAssertTrue(viewModel.showConflictMergeView)
        XCTAssertEqual(viewModel.conflictOutputText, document.outputText)
    }

    func testSetAllOursSelectedChecksEveryConflictBlock() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha",
                "<<<<<<< Current",
                "current-1",
                "||||||| Base",
                "base-1",
                "=======",
                "incoming-1",
                ">>>>>>> Incoming",
                "middle",
                "<<<<<<< Current",
                "current-2",
                "||||||| Base",
                "base-2",
                "=======",
                "incoming-2",
                ">>>>>>> Incoming",
                "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "middle", "base-2", "omega"],
            oursLines: ["alpha", "current-1", "middle", "current-2", "omega"],
            theirsLines: ["alpha", "incoming-1", "middle", "incoming-2", "omega"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        let document = ConflictEditorDocument(sides: sides)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.conflictOutputLines = document.outputLines

        viewModel.setAllOursSelected(true)

        XCTAssertTrue(viewModel.allOursSelected)
        XCTAssertEqual(
            viewModel.conflictEditorDocument?.blocks.map(\.selectedSources.current),
            [true, true]
        )
    }

    func testSetAllTheirsSelectedChecksEveryConflictBlock() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha",
                "<<<<<<< Current",
                "current-1",
                "||||||| Base",
                "base-1",
                "=======",
                "incoming-1",
                ">>>>>>> Incoming",
                "middle",
                "<<<<<<< Current",
                "current-2",
                "||||||| Base",
                "base-2",
                "=======",
                "incoming-2",
                ">>>>>>> Incoming",
                "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "middle", "base-2", "omega"],
            oursLines: ["alpha", "current-1", "middle", "current-2", "omega"],
            theirsLines: ["alpha", "incoming-1", "middle", "incoming-2", "omega"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        let document = ConflictEditorDocument(sides: sides)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.conflictOutputLines = document.outputLines

        viewModel.setAllTheirsSelected(true)

        XCTAssertTrue(viewModel.allTheirsSelected)
        XCTAssertEqual(
            viewModel.conflictEditorDocument?.blocks.map(\.selectedSources.incoming),
            [true, true]
        )
    }

    func testUndoRestoresConflictSelectionStateAndOutputText() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha",
                "<<<<<<< Current",
                "current-1",
                "||||||| Base",
                "base-1",
                "=======",
                "incoming-1",
                ">>>>>>> Incoming",
                "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "omega"],
            oursLines: ["alpha", "current-1", "omega"],
            theirsLines: ["alpha", "incoming-1", "omega"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        let document = ConflictEditorDocument(sides: sides)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.conflictOutputLines = document.outputLines
        viewModel.conflictUndoManager.removeAllActions()

        viewModel.toggleOurs(0)
        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "current-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, true)

        viewModel.conflictUndoManager.undo()

        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "base-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, false)

        viewModel.conflictUndoManager.redo()

        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "current-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, true)
    }

    func testUndoAfterManualConflictEditRevertsEditBeforeSelection() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha",
                "<<<<<<< Current",
                "current-1",
                "||||||| Base",
                "base-1",
                "=======",
                "incoming-1",
                ">>>>>>> Incoming",
                "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "omega"],
            oursLines: ["alpha", "current-1", "omega"],
            theirsLines: ["alpha", "incoming-1", "omega"],
            oursLabel: "Current",
            theirsLabel: "Incoming"
        )

        let document = ConflictEditorDocument(sides: sides)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.conflictOutputLines = document.outputLines
        viewModel.conflictUndoManager.removeAllActions()

        viewModel.toggleOurs(0)
        viewModel.updateConflictOutputText("alpha\ncurrent-1-edited\nomega")

        viewModel.undoConflictAction()
        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "current-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, true)

        viewModel.undoConflictAction()
        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "base-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, false)

        viewModel.undoConflictAction()
        XCTAssertEqual(viewModel.conflictOutputLines, ["alpha", "base-1", "omega"])
        XCTAssertEqual(viewModel.conflictEditorDocument?.blocks.first?.selectedSources.current, false)
    }

    func testChangingGraphDisplayModeClearsSelectionForCommitOutsideVisibleScope() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let visible = CommitInfo(
            hash: String(repeating: "1", count: 40),
            shortHash: "1111111",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "visible",
            refs: []
        )
        let hidden = CommitInfo(
            hash: String(repeating: "2", count: 40),
            shortHash: "2222222",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "hidden",
            refs: []
        )

        viewModel.commits = [visible, hidden]
        viewModel.setCurrentBranchHashesForTesting([visible.hash])
        viewModel.selectedCommit = hidden
        viewModel.selectedDiffFile = DiffFile(additions: 1, deletions: 0, path: "tracked.txt")
        viewModel.fileDiffContent = "diff"
        viewModel.selectedFilePaths = ["tracked.txt"]
        viewModel.selectedFileListContext = .committed

        viewModel.graphDisplayMode = .current

        XCTAssertNil(viewModel.selectedCommit)
        XCTAssertNil(viewModel.selectedDiffFile)
        XCTAssertEqual(viewModel.fileDiffContent, "")
        XCTAssertTrue(viewModel.selectedFilePaths.isEmpty)
        XCTAssertNil(viewModel.selectedFileListContext)
    }

    func testCurrentGraphModeLoadsAdditionalPagesWhenFirstPageHasNoCurrentBranchCommits() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let initialHash = try repo.commitAll(
            message: "initial",
            environment: gitDateEnv("2026-01-01T00:00:00Z")
        )

        try repo.run(["checkout", "-b", "feature"])
        try repo.writeFile("file.txt", contents: "feature\n")
        let featureHash = try repo.commitAll(
            message: "feature",
            environment: gitDateEnv("2026-01-02T00:00:00Z")
        )

        try repo.run(["checkout", "main"])
        try repo.writeFile("file.txt", contents: "main 1\n")
        _ = try repo.commitAll(
            message: "main-1",
            environment: gitDateEnv("2026-01-03T00:00:00Z")
        )
        try repo.writeFile("file.txt", contents: "main 2\n")
        _ = try repo.commitAll(
            message: "main-2",
            environment: gitDateEnv("2026-01-04T00:00:00Z")
        )
        try repo.writeFile("file.txt", contents: "main 3\n")
        let newestMainHash = try repo.commitAll(
            message: "main-3",
            environment: gitDateEnv("2026-01-05T00:00:00Z")
        )

        try repo.run(["checkout", "feature"])

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()

        XCTAssertEqual(viewModel.currentBranch, "feature")
        XCTAssertEqual(viewModel.commits.map(\.hash), [newestMainHash])
        XCTAssertFalse(viewModel.commits.contains(where: { $0.hash == featureHash }))
        XCTAssertFalse(viewModel.commits.contains(where: { $0.hash == initialHash }))

        viewModel.graphDisplayMode = .current
        await viewModel.ensureCurrentGraphCommitsAreLoaded()

        XCTAssertFalse(viewModel.graphDisplayCommits.isEmpty)
        XCTAssertEqual(viewModel.graphDisplayCommits.first?.hash, featureHash)
        XCTAssertTrue(viewModel.commits.contains(where: { $0.hash == featureHash }))
    }

    func testCurrentGraphModePreservesSelectedCommitWhilePagingInOlderCurrentBranchCommits() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "file\n")
        let initialHash = try repo.commitAll(
            message: "initial",
            environment: gitDateEnv("2026-01-01T00:00:00Z")
        )

        try repo.run(["checkout", "-b", "feature"])
        try repo.writeFile("file.txt", contents: "feature\n")
        let featureHash = try repo.commitAll(
            message: "feature",
            environment: gitDateEnv("2026-01-02T00:00:00Z")
        )

        try repo.run(["checkout", "main"])
        try repo.writeFile("file.txt", contents: "main 1\n")
        _ = try repo.commitAll(
            message: "main-1",
            environment: gitDateEnv("2026-01-03T00:00:00Z")
        )
        try repo.writeFile("file.txt", contents: "main 2\n")
        _ = try repo.commitAll(
            message: "main-2",
            environment: gitDateEnv("2026-01-04T00:00:00Z")
        )

        try repo.run(["checkout", "feature"])

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()

        XCTAssertFalse(viewModel.commits.contains(where: { $0.hash == featureHash }))

        viewModel.selectedCommit = makeCommit(hash: featureHash, parentHashes: [initialHash], message: "feature")
        viewModel.graphDisplayMode = .current
        await viewModel.ensureCurrentGraphCommitsAreLoaded()

        XCTAssertEqual(viewModel.selectedCommit?.hash, featureHash)
        XCTAssertTrue(viewModel.graphDisplayCommits.contains(where: { $0.hash == featureHash }))
    }

    func testCurrentGraphModeLoadsPastUncommittedEntryWhenFirstPageHasNoCurrentBranchCommits() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        _ = try repo.commitAll(
            message: "initial",
            environment: gitDateEnv("2026-01-01T00:00:00Z")
        )

        try repo.run(["checkout", "-b", "feature"])
        try repo.writeFile("file.txt", contents: "feature\n")
        let featureHash = try repo.commitAll(
            message: "feature",
            environment: gitDateEnv("2026-01-02T00:00:00Z")
        )

        try repo.run(["checkout", "main"])
        try repo.writeFile("file.txt", contents: "main 1\n")
        _ = try repo.commitAll(
            message: "main-1",
            environment: gitDateEnv("2026-01-03T00:00:00Z")
        )
        try repo.writeFile("file.txt", contents: "main 2\n")
        _ = try repo.commitAll(
            message: "main-2",
            environment: gitDateEnv("2026-01-04T00:00:00Z")
        )

        try repo.run(["checkout", "feature"])
        try repo.appendFile("file.txt", contents: "dirty\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()
        viewModel.graphDisplayMode = .current
        await viewModel.ensureCurrentGraphCommitsAreLoaded()

        XCTAssertEqual(viewModel.graphDisplayCommits.first?.hash, CommitInfo.uncommittedHash)
        XCTAssertTrue(viewModel.graphDisplayCommits.contains(where: { $0.hash == featureHash }))
    }

    func testNavigateToHiddenCurrentBranchCommitKeepsCurrentGraphMode() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let firstHash = try repo.commitAll(message: "first")
        try repo.writeFile("file.txt", contents: "second\n")
        _ = try repo.commitAll(message: "second")
        try repo.writeFile("file.txt", contents: "third\n")
        let thirdHash = try repo.commitAll(message: "third")

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()
        viewModel.graphDisplayMode = .current

        XCTAssertEqual(viewModel.graphDisplayCommits.map(\.hash), [thirdHash])

        await viewModel.navigateToCommit(hash: firstHash)

        XCTAssertEqual(viewModel.graphDisplayMode, .current)
        XCTAssertEqual(viewModel.selectedCommit?.hash, firstHash)
        XCTAssertEqual(viewModel.scrollToCommitHash, firstHash)
        XCTAssertTrue(viewModel.graphDisplayCommits.contains(where: { $0.hash == firstHash }))
    }

    func testNavigateToHiddenDetachedHeadCommitInCurrentModeSwitchesToAllBeforeNavigating() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let firstHash = try repo.commitAll(message: "first")
        try repo.writeFile("file.txt", contents: "second\n")
        let secondHash = try repo.commitAll(message: "second")
        try repo.run(["checkout", firstHash])

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        viewModel.graphDisplayMode = .current

        XCTAssertEqual(viewModel.graphDisplayCommits.map(\.hash), [firstHash])

        await viewModel.navigateToCommit(hash: secondHash)

        XCTAssertEqual(viewModel.graphDisplayMode, .all)
        XCTAssertEqual(viewModel.selectedCommit?.hash, secondHash)
        XCTAssertEqual(viewModel.graphDisplayCommits.map(\.hash), [secondHash, firstHash])
        XCTAssertEqual(viewModel.scrollToCommitHash, secondHash)
    }

    func testLoadAllIncludesDetachedHeadOnlyCommitInGraph() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let initialHash = try repo.commitAll(message: "first")
        try repo.run(["checkout", initialHash])
        try repo.writeFile("file.txt", contents: "detached\n")
        let detachedHash = try repo.commitAll(message: "detached")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        XCTAssertTrue(viewModel.isDetachedHead)
        XCTAssertEqual(viewModel.currentBranch, String(detachedHash.prefix(7)))
        XCTAssertEqual(viewModel.commits.first?.hash, detachedHash)
    }

    func testLoadAllSwitchesCurrentGraphModeToAllWhenHeadIsDetached() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let initialHash = try repo.commitAll(message: "first")
        try repo.writeFile("file.txt", contents: "second\n")
        _ = try repo.commitAll(message: "second")
        try repo.run(["checkout", initialHash])

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        viewModel.graphDisplayMode = .current

        await viewModel.loadAll()

        XCTAssertTrue(viewModel.isDetachedHead)
        XCTAssertEqual(viewModel.graphDisplayMode, .all)
    }

    func testNavigateToShortDetachedHeadHashSelectsHeadCommit() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "base\n")
        let initialHash = try repo.commitAll(message: "first")
        try repo.run(["checkout", initialHash])
        try repo.writeFile("file.txt", contents: "detached\n")
        let detachedHash = try repo.commitAll(message: "detached")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        XCTAssertTrue(viewModel.isDetachedHead)
        XCTAssertEqual(viewModel.currentBranch, String(detachedHash.prefix(7)))

        await viewModel.navigateToCommit(hash: viewModel.currentBranch)

        XCTAssertEqual(viewModel.selectedCommit?.hash, detachedHash)
        XCTAssertEqual(viewModel.scrollToCommitHash, detachedHash)
    }

    func testLoadAllPrependsUncommittedEntryForDirtyRepository() async {
        let repo = try! TemporaryGitRepository()
        try! repo.writeFile("tracked.txt", contents: "one\n")
        try! repo.commitAll(message: "initial")
        try! repo.appendFile("tracked.txt", contents: "two\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        XCTAssertEqual(viewModel.fileStatuses.map(\.path), ["tracked.txt"])
        XCTAssertEqual(viewModel.commits.first?.hash, CommitInfo.uncommittedHash)
        XCTAssertEqual(viewModel.commits.first?.message, "1 changed")
        XCTAssertEqual(viewModel.commits.dropFirst().first?.message, "initial")
    }

    func testLoadAllSummarizesStagedAndUnstagedCountsSeparatelyForSameFile() async {
        let repo = try! TemporaryGitRepository()
        try! repo.writeFile("tracked.txt", contents: "one\n")
        try! repo.commitAll(message: "initial")

        try! repo.writeFile("tracked.txt", contents: "one\ntwo\n")
        try! repo.run(["add", "tracked.txt"])
        try! repo.appendFile("tracked.txt", contents: "three\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        XCTAssertEqual(viewModel.fileStatuses.first?.statusCode, "MM")
        XCTAssertEqual(viewModel.commits.first?.hash, CommitInfo.uncommittedHash)
        XCTAssertEqual(viewModel.commits.first?.message, "1 staged, 1 unstaged")
    }

    func testSelectDiffFileUsesImagePresentationForBinaryImages() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("diagram.png")
        try onePixelPNGData.write(to: imageURL)

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        viewModel.selectedCommit = viewModel.commits.first
        let file = DiffFile(additions: 0, deletions: 0, path: "diagram.png")
        await viewModel.selectDiffFile(file, context: .committed)

        XCTAssertEqual(viewModel.selectedDiffVisualContent?.kind, .image)
        XCTAssertNil(viewModel.parsedDiff)
    }

    func testSelectDiffFileUsesBinaryPlaceholderForUnreadableNonImages() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let binaryURL = URL(fileURLWithPath: repo.path).appendingPathComponent("archive.bin")
        try Data([0x00, 0xFF, 0x7F, 0x10]).write(to: binaryURL)

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        viewModel.selectedCommit = viewModel.commits.first
        let file = DiffFile(additions: 0, deletions: 0, path: "archive.bin")
        await viewModel.selectDiffFile(file, context: .committed)

        XCTAssertEqual(viewModel.selectedDiffVisualContent?.kind, .binary)
        XCTAssertNil(viewModel.parsedDiff)
    }

    func testOpenFilePreviewUsesImagePresentationForBinaryImages() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("preview.png")
        try onePixelPNGData.write(to: imageURL)

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        await viewModel.openFilePreview(path: "preview.png", context: .committed)

        XCTAssertEqual(viewModel.fileInspectorMode, .preview)
        XCTAssertEqual(viewModel.fileInspectorVisualContent?.kind, .image)
    }

    func testReflogSourceOptionsIncludeCurrentBranchAfterHeadOption() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        viewModel.currentBranch = "feature/test"

        XCTAssertEqual(
            viewModel.reflogSourceOptions,
            [
                ReflogSourceOption(refName: "HEAD", title: "HEAD"),
                ReflogSourceOption(refName: "refs/heads/feature/test", title: "feature/test"),
            ]
        )
    }

    func testCanNavigateToCommitUsesCurrentLoadStateAndRecoveredCommits() async throws {
        let pendingViewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        XCTAssertFalse(pendingViewModel.canNavigateToCommit(hash: nil))
        XCTAssertTrue(pendingViewModel.canNavigateToCommit(hash: "abc1234"))

        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let loadedViewModel = RepoViewModel(path: repo.path, name: "repo")
        await loadedViewModel.loadAll()

        let existingHash = try XCTUnwrap(loadedViewModel.commits.first?.hash)
        XCTAssertTrue(loadedViewModel.canNavigateToCommit(hash: String(existingHash.prefix(10))))

        let recovered = CommitInfo(
            hash: String(repeating: "e", count: 40),
            shortHash: "eeeeeee",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Recovered",
            refs: []
        )
        loadedViewModel.reflogRecoveredCommits = [recovered]

        XCTAssertTrue(loadedViewModel.canNavigateToCommit(hash: String(recovered.hash.prefix(12))))
        XCTAssertFalse(loadedViewModel.canNavigateToCommit(hash: String(repeating: "f", count: 40)))
    }

    func testLoadAllKeepsCleanRepositoryWithoutUncommittedEntry() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        XCTAssertTrue(viewModel.fileStatuses.isEmpty)
        XCTAssertFalse(viewModel.commits.contains(where: \.isUncommitted))
        XCTAssertEqual(viewModel.commits.first?.message, "initial")
    }

    func testSelectCommitForUncommittedPrefersFirstUnstagedFile() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        try repo.writeFile("b.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("a.txt", contents: "unstaged\n")
        try repo.appendFile("b.txt", contents: "staged\n")
        try repo.run(["add", "b.txt"])

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let uncommitted = try XCTUnwrap(viewModel.commits.first(where: \.isUncommitted))

        await viewModel.selectCommit(uncommitted)

        XCTAssertEqual(viewModel.selectedCommit?.hash, CommitInfo.uncommittedHash)
        XCTAssertEqual(viewModel.selectedDiffFile?.path, "a.txt")
        XCTAssertEqual(viewModel.currentDiffContext, .unstaged)
        XCTAssertEqual(viewModel.selectedFilePaths, ["a.txt"])
        XCTAssertEqual(viewModel.selectedFileListContext, .unstaged)
    }

    func testSelectCommitForCommittedLoadsDiffFilesAndAutoSelectsFirstFile() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")
        try repo.commitAll(message: "second")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let latestCommit = try XCTUnwrap(viewModel.commits.first)

        await viewModel.selectCommit(latestCommit)

        XCTAssertEqual(viewModel.selectedCommit?.hash, latestCommit.hash)
        XCTAssertEqual(viewModel.diffFiles.map(\.path), ["tracked.txt"])
        XCTAssertEqual(viewModel.selectedDiffFile?.path, "tracked.txt")
        XCTAssertEqual(viewModel.currentDiffContext, .committed)
        XCTAssertTrue(viewModel.fileDiffContent.contains("+two"))
    }

    func testNavigateToCommitSelectsExistingCommitByPrefix() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")
        try repo.commitAll(message: "second")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let targetCommit = try XCTUnwrap(viewModel.commits.first)
        let prefix = String(targetCommit.hash.prefix(10))

        await viewModel.navigateToCommit(hash: prefix)

        XCTAssertEqual(viewModel.selectedCommit?.hash, targetCommit.hash)
        XCTAssertEqual(viewModel.scrollToCommitHash, targetCommit.hash)
    }

    func testCommitNavigationIndexSkipsAmbiguousShortHashesWithoutCrashing() async {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let ambiguousShortHash = "abc1234"
        let first = CommitInfo(
            hash: ambiguousShortHash + String(repeating: "0", count: 33),
            shortHash: ambiguousShortHash,
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-04-01",
            message: "first",
            refs: []
        )
        let second = CommitInfo(
            hash: ambiguousShortHash + String(repeating: "1", count: 33),
            shortHash: ambiguousShortHash,
            parentHashes: [first.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-04-01",
            message: "second",
            refs: []
        )
        let unique = CommitInfo(
            hash: "def5678" + String(repeating: "2", count: 33),
            shortHash: "def5678",
            parentHashes: [second.hash],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-04-01",
            message: "unique",
            refs: []
        )

        viewModel.commits = [unique, second, first]

        XCTAssertTrue(viewModel.canNavigateToCommit(hash: ambiguousShortHash))

        await viewModel.navigateToCommit(hash: unique.shortHash)

        XCTAssertEqual(viewModel.selectedCommit?.hash, unique.hash)
        XCTAssertEqual(viewModel.scrollToCommitHash, unique.hash)
    }

    func testScrollToCommitForBranchSelectsLoadedCommitByShortHash() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let initialHash = try repo.commitAll(message: "initial")
        try repo.run(["branch", "feature", initialHash])

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let branch = try XCTUnwrap(viewModel.localBranches.first(where: { $0.name == "feature" }))

        await viewModel.scrollToCommitForBranch(branch)

        XCTAssertEqual(viewModel.selectedCommit?.hash, initialHash)
        XCTAssertEqual(viewModel.scrollToCommitHash, initialHash)
    }

    func testRefreshAfterActivationReloadsCommitsCreatedWhileInactive() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let initialHash = try repo.commitAll(message: "initial")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        XCTAssertEqual(viewModel.commits.first?.hash, initialHash)

        try repo.appendFile("tracked.txt", contents: "two\n")
        let secondHash = try repo.commitAll(message: "second")

        await viewModel.refreshAfterActivation()

        XCTAssertEqual(viewModel.headCommitHash, secondHash)
        XCTAssertTrue(viewModel.commits.contains(where: { $0.hash == secondHash && $0.message == "second" }))
        let refOwner = try XCTUnwrap(viewModel.commits.first(where: { $0.refs.contains(where: { $0.contains("main") }) }))
        XCTAssertEqual(refOwner.hash, secondHash)
    }

    func testPerformCompareWithWorkingDirectoryLoadsCompareDiffAndExitClearsState() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let baseCommit = try XCTUnwrap(viewModel.commits.first(where: { !$0.isUncommitted }))

        await viewModel.performCompareWithWorkingDirectory(baseCommit)

        XCTAssertTrue(viewModel.isCompareMode)
        XCTAssertEqual(viewModel.compareBaseHash, baseCommit.hash)
        XCTAssertEqual(viewModel.diffFiles.map(\.path), ["tracked.txt"])

        let file = try XCTUnwrap(viewModel.diffFiles.first)
        await viewModel.selectCompareFile(file)
        XCTAssertEqual(viewModel.selectedDiffFile?.path, "tracked.txt")
        XCTAssertTrue(viewModel.fileDiffContent.contains("+two"))

        viewModel.exitCompareMode()
        XCTAssertFalse(viewModel.isCompareMode)
        XCTAssertNil(viewModel.compareBaseHash)
        XCTAssertTrue(viewModel.diffFiles.isEmpty)
        XCTAssertNil(viewModel.selectedDiffFile)
        XCTAssertEqual(viewModel.fileDiffContent, "")
    }

    func testHidingReflogOverlayClearsRecoveredSelectionNotPresentInCommits() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let recoveredCommit = CommitInfo(
            hash: String(repeating: "9", count: 40),
            shortHash: "9999999",
            parentHashes: [],
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-03-29",
            message: "Recovered",
            refs: []
        )

        viewModel.showReflogOverlay = true
        viewModel.selectedCommit = recoveredCommit
        viewModel.selectedDiffFile = DiffFile(additions: 1, deletions: 0, path: "tracked.txt")
        viewModel.fileDiffContent = "diff"
        viewModel.selectedFilePaths = ["tracked.txt"]
        viewModel.selectedFileListContext = .committed

        viewModel.showReflogOverlay = false

        XCTAssertNil(viewModel.selectedCommit)
        XCTAssertNil(viewModel.selectedDiffFile)
        XCTAssertEqual(viewModel.fileDiffContent, "")
        XCTAssertTrue(viewModel.selectedFilePaths.isEmpty)
        XCTAssertNil(viewModel.selectedFileListContext)
    }

    func testToggleFileSelectionRangeKeepsAnchorAndContextSwitchResetsSelection() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let ordered = ["a.txt", "b.txt", "c.txt", "d.txt"]

        viewModel.toggleFileSelection("a.txt", context: .unstaged, isMulti: false, orderedPaths: ordered)
        viewModel.toggleFileSelection("c.txt", context: .unstaged, isMulti: false, isRange: true, orderedPaths: ordered)
        XCTAssertEqual(viewModel.selectedFilePaths, ["a.txt", "b.txt", "c.txt"])

        viewModel.toggleFileSelection("d.txt", context: .unstaged, isMulti: false, isRange: true, orderedPaths: ordered)
        XCTAssertEqual(viewModel.selectedFilePaths, ["a.txt", "b.txt", "c.txt", "d.txt"])

        viewModel.toggleFileSelection("z.txt", context: .staged, isMulti: false)
        XCTAssertEqual(viewModel.selectedFilePaths, ["z.txt"])
        XCTAssertEqual(viewModel.selectedFileListContext, .staged)
    }

    func testLoadReflogClearsStateWhenLoadingFails() async {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)/missing", name: "repo")
        let hash = String(repeating: "a", count: 40)
        viewModel.reflogEntries = [
            ReflogEntryInfo(
                refName: "HEAD",
                index: 0,
                oldOID: nil,
                newOID: hash,
                message: "commit",
                kind: .commit,
                committerName: "Test",
                committerEmail: "test@example.com",
                date: "2026-03-29 10:00:00 +0000"
            )
        ]
        viewModel.reflogEntriesByCommitHash = [hash: viewModel.reflogEntries]
        viewModel.reflogRecoveredCommits = [
            CommitInfo(
                hash: hash,
                shortHash: "aaaaaaa",
                parentHashes: [],
                authorName: "Test",
                authorEmail: "test@example.com",
                date: "2026-03-29",
                message: "Recovered",
                refs: []
            )
        ]
        viewModel.reflogRecoveryEntriesByCommitHash = [hash: viewModel.reflogEntries]

        await viewModel.loadReflog()

        XCTAssertTrue(viewModel.reflogEntries.isEmpty)
        XCTAssertTrue(viewModel.reflogEntriesByCommitHash.isEmpty)
        XCTAssertTrue(viewModel.reflogRecoveredCommits.isEmpty)
        XCTAssertTrue(viewModel.reflogRecoveryEntriesByCommitHash.isEmpty)
    }

    // MARK: - checkForRebaseConflict error surfacing

    func testCheckForRebaseConflictWithNoActiveRebaseShowsErrorToast() async {
        // A path that doesn't exist has no rebase in progress, so rebaseState() returns nil.
        let viewModel = RepoViewModel(path: "/tmp/nonexistent-\(UUID().uuidString)", name: "repo")
        XCTAssertNil(viewModel.toastMessage)

        await viewModel.checkForRebaseConflict(errorMessage: "cannot rebase: You have unstaged changes.")

        XCTAssertNotNil(viewModel.toastMessage, "Expected an error toast to be shown when squash/rebase fails with no conflict")
        XCTAssertEqual(viewModel.toastMessage?.style, .error)
        XCTAssertTrue(
            viewModel.toastMessage?.detail.contains("unstaged") == true,
            "Toast detail should contain the original error message"
        )
    }

    func testCheckForRebaseConflictWithNilErrorMessageShowsNoToast() async {
        let viewModel = RepoViewModel(path: "/tmp/nonexistent-\(UUID().uuidString)", name: "repo")

        await viewModel.checkForRebaseConflict(errorMessage: nil)

        XCTAssertNil(viewModel.toastMessage, "No toast should appear when there is no error message")
    }

    private func makeCommit(hash: String, parentHashes: [String] = [], message: String) -> CommitInfo {
        CommitInfo(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            parentHashes: parentHashes,
            authorName: "Test",
            authorEmail: "test@example.com",
            date: "2026-04-01",
            message: message,
            refs: []
        )
    }

    private func gitDateEnv(_ iso8601: String) -> [String: String] {
        [
            "GIT_AUTHOR_DATE": iso8601,
            "GIT_COMMITTER_DATE": iso8601
        ]
    }
}

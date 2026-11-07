import XCTest
@testable import GitN

@MainActor
final class RepoViewModelBehaviorTests: XCTestCase {
    private let onePixelPNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN6kAAAAASUVORK5CYII=")!

    func testFileEventsDuringOperationRefreshAfterOperationFinishes() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "before\n")
        try repo.commitAll(message: "initial")
        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        XCTAssertTrue(viewModel.fileStatuses.isEmpty)

        viewModel.operationInProgress = true
        try repo.writeFile("tracked.txt", contents: "after\n")
        await viewModel.handleFileSystemChanges([.workingDirectory, .index])
        XCTAssertTrue(viewModel.fileStatuses.isEmpty)

        viewModel.operationInProgress = false
        for _ in 0..<100 where viewModel.fileStatuses.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.fileStatuses.map(\.path), ["tracked.txt"])
    }

    func testHeadEventDuringLoadTriggersDeferredFullRefresh() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "before\n")
        try repo.commitAll(message: "initial")
        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        viewModel.isLoading = true
        try repo.writeFile("tracked.txt", contents: "after\n")
        await viewModel.handleFileSystemChanges([.head, .workingDirectory])
        XCTAssertTrue(viewModel.fileStatuses.isEmpty)

        viewModel.isLoading = false
        for _ in 0..<100 where viewModel.fileStatuses.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.fileStatuses.map(\.path), ["tracked.txt"])
    }

    func testStashInspectorUsesSnapshotForMarkdownInsteadOfCurrentWorktree() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("notes.md", contents: "stashed\n")
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "markdown")
        try repo.writeFile("notes.md", contents: "current worktree\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.selectStash(stash)
        let file = try XCTUnwrap(viewModel.diffFiles.first { $0.path == "notes.md" })
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertEqual(viewModel.fileInspectorDiffBaseText, "base\n")
        XCTAssertEqual(viewModel.fileInspectorContent, "stashed\n")
        XCTAssertFalse(viewModel.isFileInspectorEditable)
    }

    func testStashInspectorReadsUntrackedMarkdownFromThirdParent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("new.md", contents: "# Stashed document\n")
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "new document", includeUntracked: true)
        try repo.writeFile("new.md", contents: "# Different worktree document\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.selectStash(stash)
        let file = try XCTUnwrap(viewModel.diffFiles.first { $0.path == "new.md" })
        XCTAssertEqual(file.changeKind, .untracked)
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .preview)

        XCTAssertEqual(viewModel.fileInspectorContent, "# Stashed document\n")
        XCTAssertFalse(viewModel.isFileInspectorEditable)
    }

    func testStashInspectorTreatsDeletedMarkdownAsEmptyNewSide() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("removed.md", contents: "# Before deletion\n")
        try repo.commitAll(message: "initial")
        try repo.run(["rm", "removed.md"])
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "remove document")
        try repo.writeFile("removed.md", contents: "# Current worktree\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.selectStash(stash)
        let file = try XCTUnwrap(viewModel.diffFiles.first { $0.path == "removed.md" })
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertEqual(viewModel.fileInspectorDiffBaseText, "# Before deletion\n")
        XCTAssertEqual(viewModel.fileInspectorContent, "")
        XCTAssertTrue(viewModel.fileDiffContent.contains("-# Before deletion"))
    }

    func testStashInspectorKeepsDeletedImageOnOldSide() async throws {
        let repo = try TemporaryGitRepository()
        try onePixelPNGData.write(to: repo.url.appendingPathComponent("removed.png"))
        try repo.commitAll(message: "initial")
        try repo.run(["rm", "removed.png"])
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "remove image")
        try Data("different worktree bytes".utf8).write(to: repo.url.appendingPathComponent("removed.png"))

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.selectStash(stash)
        let file = try XCTUnwrap(viewModel.diffFiles.first { $0.path == "removed.png" })
        XCTAssertEqual(file.changeKind, .deleted)
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)

        XCTAssertEqual(viewModel.fileInspectorContent, "")
        XCTAssertEqual(viewModel.selectedDiffVisualContent?.oldData, onePixelPNGData)
        XCTAssertNil(viewModel.selectedDiffVisualContent?.newData)
        XCTAssertEqual(viewModel.fileInspectorVisualContent?.oldData, onePixelPNGData)
    }

    func testSidebarStashApplyKeepsSelectedEntryAndRefreshesFiles() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("notes.md", contents: "stashed\n")
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "notes")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.performStashApplyAt(stash: stash)

        XCTAssertEqual(try repo.readFile("notes.md"), "stashed\n")
        XCTAssertEqual(viewModel.stashes.map(\.oid), [oid])
        XCTAssertEqual(viewModel.fileStatuses.map(\.path), ["notes.md"])
        XCTAssertNil(viewModel.operationError)
        XCTAssertFalse(viewModel.operationInProgress)
    }

    func testSidebarStashPopDropsSelectedEntryOnlyAfterApply() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("notes.md", contents: "stashed\n")
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "notes")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.performStashPopAt(stash: stash)

        XCTAssertEqual(try repo.readFile("notes.md"), "stashed\n")
        XCTAssertTrue(viewModel.stashes.isEmpty)
        XCTAssertEqual(viewModel.fileStatuses.map(\.path), ["notes.md"])
        XCTAssertNil(viewModel.operationError)
        XCTAssertFalse(viewModel.operationInProgress)
    }

    func testSidebarStashPopFailureRetainsEntryAndReportsError() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("notes.md", contents: "stashed\n")
        let service = GitService(repoPath: repo.path)
        let oid = try await service.stashSave(message: "notes")
        try repo.writeFile("notes.md", contents: "current edits\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let stash = try XCTUnwrap(viewModel.stashes.first { $0.oid == oid })
        await viewModel.performStashPopAt(stash: stash)

        XCTAssertEqual(try repo.readFile("notes.md"), "current edits\n")
        XCTAssertEqual(viewModel.stashes.map(\.oid), [oid])
        XCTAssertTrue(viewModel.operationError?.contains("notes.md") == true)
        XCTAssertFalse(viewModel.operationInProgress)
    }

    func testFailedBranchPullRestoresAutoStashOnlyAfterReturningToOriginalBranch() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.run(["branch", "topic"])
        try repo.writeFile("notes.md", contents: "dirty work\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let topic = try XCTUnwrap(viewModel.localBranches.first { $0.name == "topic" })
        await viewModel.performPullBranch(topic)

        XCTAssertEqual(try repo.run(["branch", "--show-current"]), "main")
        XCTAssertEqual(try repo.readFile("notes.md"), "dirty work\n")
        XCTAssertEqual(try repo.run(["stash", "list"]), "")
        XCTAssertTrue(viewModel.operationError?.contains("Pull topic failed") == true)
    }

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

    func testFilesSectionIsCollapsedByDefault() {
        let path = "/tmp/\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: "SidebarCollapsedSections.\(path)")
        UserDefaults.standard.removeObject(forKey: "SidebarCollapsedSections.\(path).defaultsApplied.v2")

        let viewModel = RepoViewModel(path: path, name: "repo")

        XCTAssertTrue(viewModel.isSectionCollapsed("files"))
    }

    func testCurrentBranchReviewCreationURLUsesPreferredHostedRemote() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        viewModel.remotes = [
            RemoteInfo(name: "backup", url: "ssh://example.com/repo.git"),
            RemoteInfo(name: "origin", url: "git@github.com:owner/repo.git"),
        ]
        viewModel.currentBranch = "feature/test"
        viewModel.isDetachedHead = false

        XCTAssertEqual(
            viewModel.currentBranchReviewCreationURL()?.absoluteString,
            "https://github.com/owner/repo/compare/feature/test?expand=1"
        )
    }

    func testCurrentBranchReviewCreationURLReturnsNilWhenDetachedHead() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        viewModel.remotes = [
            RemoteInfo(name: "origin", url: "git@gitlab.example.com:group/repo.git"),
        ]
        viewModel.currentBranch = "HEAD"
        viewModel.isDetachedHead = true

        XCTAssertNil(viewModel.currentBranchReviewCreationURL())
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

        XCTAssertEqual(viewModel.toastMessage?.title, "Unresolved Conflicts")
        XCTAssertEqual(viewModel.toastMessage?.style, .warning)
        XCTAssertTrue(viewModel.showConflictMergeView)
        XCTAssertEqual(viewModel.conflictOutputText, document.outputText)
    }

    func testSaveConflictResolutionRefusesPartiallyResolvedFile() async {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        let sides = GitService.buildConflictSides(
            mergedText: [
                "alpha", "<<<<<<< Current", "current-1", "||||||| Base", "base-1",
                "=======", "incoming-1", ">>>>>>> Incoming", "middle",
                "<<<<<<< Current", "current-2", "||||||| Base", "base-2",
                "=======", "incoming-2", ">>>>>>> Incoming", "omega",
            ].joined(separator: "\n"),
            baseLines: ["alpha", "base-1", "middle", "base-2", "omega"],
            oursLines: ["alpha", "current-1", "middle", "current-2", "omega"],
            theirsLines: ["alpha", "incoming-1", "middle", "incoming-2", "omega"],
            oursLabel: "Current", theirsLabel: "Incoming"
        )
        var document = ConflictEditorDocument(sides: sides)
        document.toggleCurrent(blockID: 0)
        viewModel.conflictMergeFile = ConflictFile(path: "file.txt", conflictCount: 2)
        viewModel.conflictEditorDocument = document
        viewModel.conflictOutputText = document.outputText
        viewModel.showConflictMergeView = true

        await viewModel.saveConflictResolution()

        XCTAssertEqual(viewModel.toastMessage?.title, "Unresolved Conflicts")
        XCTAssertEqual(viewModel.conflictEditorDocument?.unresolvedBlockIDs, [1])
        XCTAssertTrue(viewModel.showConflictMergeView)
    }

    func testSaveConflictResolutionAllowsManualOutputChangesWithoutSelectedHunks() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "alpha\nbase-1\nomega\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("file.txt", contents: "alpha\ncurrent-1\nomega\n")
        try repo.commitAll(message: "ours")
        try repo.run(["checkout", "main"])
        try repo.writeFile("file.txt", contents: "alpha\nincoming-1\nomega\n")
        try repo.commitAll(message: "theirs")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.openConflictMerge(ConflictFile(path: "file.txt", conflictCount: 1))
        XCTAssertNotNil(viewModel.conflictEditorDocument)
        viewModel.updateConflictOutputText([
            "alpha",
            "manual-resolution",
            "omega",
        ].joined(separator: "\n"))

        await viewModel.saveConflictResolution()

        XCTAssertEqual(viewModel.toastMessage?.title, "Saved")
        XCTAssertFalse(viewModel.showConflictMergeView)
        XCTAssertEqual(try repo.readFile("file.txt"), "alpha\nmanual-resolution\nomega")
        XCTAssertEqual(try repo.run(["diff", "--cached", "--name-only"]), "file.txt")
    }

    func testSaveConflictResolutionInFallbackModeMarksFileResolved() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.bin", contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("file.bin", contents: "ours\n")
        try repo.commitAll(message: "ours")
        try repo.run(["checkout", "main"])
        try repo.writeFile("file.bin", contents: "theirs\n")
        try repo.commitAll(message: "theirs")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        viewModel.conflictMergeFile = ConflictFile(path: "file.bin", conflictCount: 1)
        viewModel.conflictFallbackMessage = "Binary conflict"
        viewModel.showConflictMergeView = true

        await viewModel.saveConflictResolution()

        XCTAssertEqual(viewModel.toastMessage?.title, "Marked Resolved")
        XCTAssertFalse(viewModel.showConflictMergeView)
        XCTAssertNil(viewModel.conflictFallbackMessage)
        XCTAssertNil(viewModel.conflictMergeFile)
    }

    func testBinaryModifyDeleteConflictRequiresExplicitChoiceInViewModel() async throws {
        let repo = try TemporaryGitRepository()
        let path = "file.bin"
        let url = repo.url.appendingPathComponent(path)
        let modified = Data([0x00, 0xff, 0x01, 0x80])
        try Data([0x00, 0x01]).write(to: url)
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.run(["rm", path])
        try repo.commitAll(message: "delete")
        try repo.run(["checkout", "main"])
        try modified.write(to: url)
        try repo.commitAll(message: "binary modify")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.openConflictMerge(ConflictFile(path: path, conflictCount: 1))
        XCTAssertTrue(viewModel.showConflictMergeView)
        XCTAssertEqual(viewModel.conflictMissingSide, .incoming)
        XCTAssertNotNil(viewModel.conflictFallbackMessage)

        await viewModel.saveConflictResolution()
        XCTAssertEqual(viewModel.toastMessage?.title, "Choose a Resolution")
        XCTAssertFalse(try repo.run(["ls-files", "-u", "--", path]).isEmpty)

        await viewModel.resolveDeleteModifyConflict(.modified)
        XCTAssertFalse(viewModel.showConflictMergeView)
        XCTAssertEqual(try Data(contentsOf: url), modified)
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", path]).isEmpty)
    }

    func testOpenWorkingTreeFilePreviewUsesWorkingTreeContentEvenWhenCommitIsSelected() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/App.swift", contents: "print(\"base\")\n")
        try repo.commitAll(message: "Initial commit")
        try repo.writeFile("Sources/App.swift", contents: "print(\"working-tree\")\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        guard let committed = viewModel.commits.first(where: { !$0.isUncommitted }) else {
            return XCTFail("Expected committed history entry")
        }

        viewModel.selectedCommit = committed

        await viewModel.openWorkingTreeFilePreview(path: "Sources/App.swift")

        XCTAssertEqual(viewModel.fileInspectorMode, .preview)
        XCTAssertEqual(viewModel.fileInspectorContext, .unstaged)
        XCTAssertEqual(viewModel.fileInspectorContent, "print(\"working-tree\")\n")
        XCTAssertTrue(viewModel.isFileInspectorEditable)
        XCTAssertEqual(viewModel.selectedWorkingTreeFilePath, "Sources/App.swift")
    }

    func testLFSGuidanceMessageExplainsInstallAndInit() {
        let message = RepoViewModel.lfsGuidanceMessage(
            for: "push",
            errorMessage: "Repository uses Git LFS, but `git lfs` is unavailable. Install Git LFS, run `git lfs install`, and retry."
        )

        XCTAssertEqual(
            message,
            "Git LFS is required to push this repository. Install Git LFS, run `git lfs install`, then retry."
        )
    }

    func testLFSGuidanceMessageIgnoresNonLFSErrors() {
        XCTAssertNil(
            RepoViewModel.lfsGuidanceMessage(for: "pull", errorMessage: "Host key verification failed")
        )
    }

    func testWorkingTreeFilesInspectorSelectionIsPreviewOnly() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("script.sh", contents: "echo hi\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        await viewModel.openWorkingTreeFilePreview(path: "script.sh")

        XCTAssertTrue(viewModel.isWorkingTreeFilesInspectorSelection)
        XCTAssertEqual(viewModel.fileInspectorMode, .preview)

        await viewModel.setFileInspectorMode(.diff)
        XCTAssertEqual(viewModel.fileInspectorMode, .preview)

        await viewModel.setFileInspectorMode(.history)
        XCTAssertEqual(viewModel.fileInspectorMode, .preview)
    }

    func testOpenFileHistorySupportsWorkingTreeFileContext() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("script.sh", contents: "echo base\n")
        try repo.commitAll(message: "Initial commit")
        try repo.writeFile("script.sh", contents: "echo changed\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        await viewModel.openFileHistory(path: "script.sh", context: .unstaged)

        XCTAssertTrue(viewModel.isFileInspectorPresented)
        XCTAssertEqual(viewModel.fileInspectorMode, .history)
        XCTAssertEqual(viewModel.fileInspectorContext, .unstaged)
        XCTAssertEqual(viewModel.fileHistoryPath, "script.sh")
        XCTAssertFalse(viewModel.fileHistoryCommits.isEmpty)
        XCTAssertEqual(viewModel.fileHistoryCommits.first?.message, "Initial commit")
    }

    func testFileHistoryComparesRenameEntryAgainstPreviousHistoryEntry() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.txt", contents: "one\n")
        _ = try repo.commitAll(message: "initial notes")

        try repo.run(["mv", "notes.txt", "journal.txt"])
        let renameHash = try repo.commitAll(message: "rename notes")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.openFileHistory(path: "journal.txt", context: .unstaged)

        guard let renameCommit = viewModel.fileHistoryCommits.first(where: { $0.hash == renameHash }) else {
            return XCTFail("Expected rename history entry")
        }

        await viewModel.selectFileHistoryCommit(renameCommit)

        XCTAssertEqual(viewModel.fileHistoryBaseText, "one\n")
        XCTAssertEqual(viewModel.fileHistoryCurrentText, "one\n")
        XCTAssertTrue(viewModel.fileHistoryParsedDiff?.hunks.isEmpty ?? false)
        XCTAssertEqual(viewModel.fileHistoryDiff, "__synthetic__")
    }

    func testFileHistorySelectionReplacesPreviousRevisionAndCloseClearsState() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "# First\n")
        let firstHash = try repo.commitAll(message: "first")
        try repo.writeFile("notes.md", contents: "# Second\n")
        let secondHash = try repo.commitAll(message: "second")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.openFileHistory(path: "notes.md", context: .unstaged)
        let first = try XCTUnwrap(viewModel.fileHistoryCommits.first { $0.hash == firstHash })
        let second = try XCTUnwrap(viewModel.fileHistoryCommits.first { $0.hash == secondHash })

        await viewModel.selectFileHistoryCommit(first)
        XCTAssertEqual(viewModel.fileHistoryCurrentText, "# First\n")

        await viewModel.selectFileHistoryCommit(second)
        XCTAssertEqual(viewModel.fileHistoryBaseText, "# First\n")
        XCTAssertEqual(viewModel.fileHistoryCurrentText, "# Second\n")
        XCTAssertNotNil(viewModel.fileHistoryParsedDiff)

        viewModel.closeFileHistory()
        XCTAssertNil(viewModel.fileHistorySelectedCommit)
        XCTAssertNil(viewModel.fileHistoryParsedDiff)
        XCTAssertTrue(viewModel.fileHistoryCurrentText.isEmpty)
        await viewModel.selectFileHistoryCommit(first)
        XCTAssertNil(viewModel.fileHistorySelectedCommit)
    }

    func testRepositoryFileHistoryPathPreservesRepoRootPathAndPrefixesRelativePath() {
        let viewModel = RepoViewModel(path: "/tmp/\(UUID().uuidString)", name: "repo")
        viewModel.fileHistoryWorkingTreePrefix = "mxz_ios_appclip/"
        viewModel.fileHistoryPath = "Manager/AppClipLock.swift"

        XCTAssertEqual(
            viewModel.repositoryFileHistoryPath("mxz_ios_appclip/Manager/AppClipLock.swift"),
            "mxz_ios_appclip/Manager/AppClipLock.swift"
        )
        XCTAssertEqual(
            viewModel.repositoryFileHistoryPath("Manager/AppClipLock.swift"),
            "mxz_ios_appclip/Manager/AppClipLock.swift"
        )
        XCTAssertEqual(
            viewModel.repositoryFileHistoryPath("Modules/MGFoundation/Sources/MGFoundation/MultiThread/MGProtect.swift"),
            "Modules/MGFoundation/Sources/MGFoundation/MultiThread/MGProtect.swift"
        )
    }

    func testRefreshAfterWorkingTreeMutationRebuildsUncommittedDiffFiles() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitignore", contents: "DerivedData/\n")
        try repo.writeFile("tracked.txt", contents: "base\n")
        try repo.commitAll(message: "Initial commit")
        try repo.writeFile("tracked.txt", contents: "tracked change\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        guard let uncommitted = viewModel.commits.first(where: \.isUncommitted) else {
            return XCTFail("Expected uncommitted entry")
        }

        await viewModel.selectCommit(uncommitted)
        XCTAssertEqual(Set(viewModel.diffFiles.map(\.path)), ["tracked.txt"])

        try repo.writeFile(".gitignore", contents: "DerivedData/\n*.xcworkspace\n")
        await viewModel.refreshAfterWorkingTreeMutation()

        XCTAssertEqual(Set(viewModel.diffFiles.map(\.path)), [".gitignore", "tracked.txt"])
    }

    func testHandleMissingWorkingTreePathClosesOpenWorkingTreePreview() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("script.sh", contents: "echo hi\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        await viewModel.openWorkingTreeFilePreview(path: "script.sh")

        XCTAssertTrue(viewModel.isFileInspectorPresented)
        XCTAssertEqual(viewModel.selectedWorkingTreeFilePath, "script.sh")

        try FileManager.default.removeItem(at: URL(fileURLWithPath: repo.path).appendingPathComponent("script.sh"))
        viewModel.handleMissingWorkingTreePath("script.sh")

        XCTAssertFalse(viewModel.isFileInspectorPresented)
        XCTAssertNil(viewModel.selectedWorkingTreeFilePath)
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

    func testSelectDiffFileUsesImagePresentationForStagedLFSImage() async throws {
        try requireGitLFS()

        let repo = try TemporaryGitRepository()
        try repo.run(["lfs", "install", "--local"])
        try repo.run(["lfs", "track", "*.png"])
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("staged-lfs.png")
        try onePixelPNGData.write(to: imageURL)
        try repo.run(["add", "staged-lfs.png"])

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        let uncommitted = try XCTUnwrap(viewModel.commits.first)
        await viewModel.selectCommit(uncommitted)
        let file = try XCTUnwrap(viewModel.diffFiles.first(where: { $0.path == "staged-lfs.png" }))
        await viewModel.selectDiffFile(file, context: .staged)

        XCTAssertEqual(viewModel.selectedDiffVisualContent?.kind, .image)
        XCTAssertEqual(viewModel.selectedDiffVisualContent?.newData, onePixelPNGData)
        XCTAssertNil(viewModel.parsedDiff)
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

    func testScrollToCommitForBranchLoadsOlderCommitWhenNotInInitialPage() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let initialHash = try repo.commitAll(
            message: "initial",
            environment: gitDateEnv("2026-01-01T00:00:00Z")
        )
        try repo.run(["branch", "feature", initialHash])
        try repo.appendFile("tracked.txt", contents: "two\n")
        _ = try repo.commitAll(
            message: "second",
            environment: gitDateEnv("2026-01-02T00:00:00Z")
        )

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()

        XCTAssertEqual(viewModel.commits.count, 1)
        XCTAssertFalse(viewModel.commits.contains(where: { $0.hash == initialHash }))

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

    func testRefreshAfterWorkingTreeMutationPromotesToFullReloadWhenExternalCheckoutChangesBranch() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "base\n")
        _ = try repo.commitAll(
            message: "main",
            environment: gitDateEnv("2026-01-01T00:00:00Z")
        )

        try repo.run(["checkout", "-b", "feature"])
        try repo.writeFile("tracked.txt", contents: "feature\n")
        let featureHash = try repo.commitAll(
            message: "feature",
            environment: gitDateEnv("2026-01-02T00:00:00Z")
        )
        try repo.run(["checkout", "main"])

        let viewModel = RepoViewModel(path: repo.path, name: "repo", commitPageSize: 1)
        await viewModel.loadAll()

        XCTAssertEqual(viewModel.currentBranch, "main")
        XCTAssertEqual(viewModel.localBranches.first(where: { $0.isCurrent })?.name, "main")

        try repo.run(["checkout", "feature"])

        await viewModel.refreshAfterWorkingTreeMutation()

        XCTAssertEqual(viewModel.currentBranch, "feature")
        XCTAssertEqual(viewModel.localBranches.first(where: { $0.isCurrent })?.name, "feature")
        XCTAssertEqual(viewModel.headCommitHash, featureHash)
        XCTAssertTrue(viewModel.commits.contains(where: { $0.hash == featureHash }))
    }

    func testRefreshAfterWorkingTreeMutationInvalidatesSidebarFileSearchIndex() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/App/LoginView.swift", contents: "struct LoginView {}\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await WorkingTreeFileSearchIndex.shared.invalidate(repositoryPath: repo.path)

        let initial = try await WorkingTreeFileSearchIndex.shared.search(
            repositoryPath: repo.path,
            query: "Login"
        )
        XCTAssertEqual(initial.matchedFilePaths, ["Sources/App/LoginView.swift"])

        try repo.writeFile("Sources/App/SignupView.swift", contents: "struct SignupView {}\n")
        try FileManager.default.removeItem(at: repo.url.appendingPathComponent("Sources/App/LoginView.swift"))

        await viewModel.refreshAfterWorkingTreeMutation()

        let refreshed = try await WorkingTreeFileSearchIndex.shared.search(
            repositoryPath: repo.path,
            query: "Signup"
        )
        let stale = try await WorkingTreeFileSearchIndex.shared.search(
            repositoryPath: repo.path,
            query: "Login"
        )

        XCTAssertEqual(refreshed.matchedFilePaths, ["Sources/App/SignupView.swift"])
        XCTAssertTrue(stale.matchedFilePaths.isEmpty)
    }

    func testPerformCompareWithWorkingDirectoryLoadsChangesAfterSelectedCommitAndExitClearsState() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")
        let selectedHash = try repo.commitAll(message: "selected")
        try repo.writeFile("later.txt", contents: "later\n")
        try repo.commitAll(message: "later")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let selectedCommit = try XCTUnwrap(viewModel.commits.first(where: { $0.hash == selectedHash }))

        await viewModel.performCompareWithWorkingDirectory(selectedCommit)

        XCTAssertTrue(viewModel.isCompareMode)
        XCTAssertEqual(viewModel.compareBaseHash, selectedHash)
        XCTAssertNil(viewModel.compareTargetHash)
        XCTAssertEqual(viewModel.diffFiles.map(\.path), ["later.txt"])

        let file = try XCTUnwrap(viewModel.diffFiles.first)
        await viewModel.selectCompareFile(file)
        XCTAssertEqual(viewModel.selectedDiffFile?.path, "later.txt")
        XCTAssertTrue(viewModel.fileDiffContent.contains("+later"))
        XCTAssertFalse(viewModel.fileDiffContent.contains("+two"))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
        XCTAssertEqual(viewModel.fileInspectorDiffBaseText, "")
        XCTAssertEqual(viewModel.fileInspectorContent, "later\n")
        XCTAssertTrue(viewModel.fileDiffContent.contains("+later"))

        viewModel.exitCompareMode()
        XCTAssertFalse(viewModel.isCompareMode)
        XCTAssertNil(viewModel.compareBaseHash)
        XCTAssertNil(viewModel.compareTargetHash)
        XCTAssertTrue(viewModel.diffFiles.isEmpty)
        XCTAssertNil(viewModel.selectedDiffFile)
        XCTAssertEqual(viewModel.fileDiffContent, "")
    }

    func testPerformCompareBetweenCommitsUsesProvidedSelectionOrder() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("ordered.txt", contents: "one\n")
        let firstHash = try repo.commitAll(message: "first")
        try repo.appendFile("ordered.txt", contents: "two\n")
        try repo.commitAll(message: "second")
        try repo.appendFile("ordered.txt", contents: "three\n")
        let thirdHash = try repo.commitAll(message: "third")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()
        let firstCommit = try XCTUnwrap(viewModel.commits.first(where: { $0.hash == firstHash }))
        let thirdCommit = try XCTUnwrap(viewModel.commits.first(where: { $0.hash == thirdHash }))

        await viewModel.performCompareBetweenCommits(base: thirdCommit, target: firstCommit)

        XCTAssertTrue(viewModel.isCompareMode)
        XCTAssertEqual(viewModel.compareBaseHash, thirdHash)
        XCTAssertEqual(viewModel.compareTargetHash, firstHash)
        XCTAssertEqual(viewModel.diffFiles.map(\.path), ["ordered.txt"])

        let file = try XCTUnwrap(viewModel.diffFiles.first)
        await viewModel.selectCompareFile(file)
        XCTAssertTrue(viewModel.fileDiffContent.contains("-two"))
        XCTAssertTrue(viewModel.fileDiffContent.contains("-three"))
        await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
        XCTAssertEqual(viewModel.fileInspectorDiffBaseText, "one\ntwo\nthree\n")
        XCTAssertEqual(viewModel.fileInspectorContent, "one\n")
        XCTAssertTrue(viewModel.fileDiffContent.contains("-two"))
        XCTAssertTrue(viewModel.fileDiffContent.contains("-three"))
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

    func testRenameWorkingTreeFileUpdatesSelectedPreviewPath() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("docs/readme.md", contents: "# Readme\n")

        let viewModel = RepoViewModel(
            path: repo.path,
            name: "repo",
            workingTreeFileOperations: WorkingTreeFileOperations(repoPath: repo.path)
        )

        await viewModel.loadWorkingTreeFilesRootIfNeeded()
        await viewModel.setWorkingTreeFolderExpanded(path: "docs", isExpanded: true)
        await viewModel.openWorkingTreeFilePreview(path: "docs/readme.md")

        let renamedPath = await viewModel.performRenameWorkingTreeItem(path: "docs/readme.md", newName: "guide.md")

        XCTAssertEqual(renamedPath, "docs/guide.md")
        XCTAssertEqual(viewModel.selectedWorkingTreeFilePath, "docs/guide.md")
        XCTAssertEqual(viewModel.fileInspectorPath, "docs/guide.md")
        XCTAssertTrue(viewModel.isFileInspectorPresented)
    }

    func testDeleteWorkingTreeFileClosesSelectedPreview() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("docs/readme.md", contents: "# Readme\n")

        let viewModel = RepoViewModel(
            path: repo.path,
            name: "repo",
            workingTreeFileOperations: WorkingTreeFileOperations(repoPath: repo.path)
        )

        await viewModel.loadWorkingTreeFilesRootIfNeeded()
        await viewModel.setWorkingTreeFolderExpanded(path: "docs", isExpanded: true)
        await viewModel.openWorkingTreeFilePreview(path: "docs/readme.md")

        await viewModel.performDeleteWorkingTreeItem(path: "docs/readme.md")

        XCTAssertNil(viewModel.selectedWorkingTreeFilePath)
        XCTAssertFalse(viewModel.isFileInspectorPresented)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("docs/readme.md").path))
    }

    func testDeleteExpandedWorkingTreeFolderKeepsRootListingOtherEntries() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("docs/readme.md", contents: "# Readme\n")
        try repo.writeFile("src/app.swift", contents: "print(\"hi\")\n")

        let viewModel = RepoViewModel(
            path: repo.path,
            name: "repo",
            workingTreeFileOperations: WorkingTreeFileOperations(repoPath: repo.path)
        )

        await viewModel.loadWorkingTreeFilesRootIfNeeded()
        await viewModel.setWorkingTreeFolderExpanded(path: "docs", isExpanded: true)

        await viewModel.performDeleteWorkingTreeItem(path: "docs")

        XCTAssertEqual(viewModel.workingTreeFiles.map(\.relativePath), ["src"])
        XCTAssertFalse(viewModel.workingTreeFolderContents.keys.contains("docs"))
    }

    // MARK: - R3: File-switch correctness (selectDiffFile transitions)

    /// Forces `maxDiffFileSize` down to 1 MB for the duration of `body` so tests can
    /// trip the "file too large" guard with small fixture files. The previous value is
    /// restored afterwards. (R3)
    private func withMaxDiffFileSizeMB(_ value: Int, _ body: () async throws -> Void) async rethrows {
        let key = RepoViewModel.maxDiffFileSizeKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try await body()
    }

    /// Writes a file whose on-disk size is exactly `megabytes` MiB so the resulting
    /// `fileTooLargeSizeMB` label is deterministic (e.g. "2.0", "3.0").
    private func writeSizedFile(_ repo: TemporaryGitRepository, path: String, megabytes: Int) throws {
        let byteCount = megabytes * 1_048_576
        try repo.writeFile(path, contents: String(repeating: "a", count: byteCount))
    }

    private func selectUncommitted(_ viewModel: RepoViewModel) async throws -> CommitInfo {
        await viewModel.loadAll()
        let uncommitted = try XCTUnwrap(
            viewModel.commits.first(where: \.isUncommitted),
            "expected an uncommitted history entry for working-tree changes"
        )
        await viewModel.selectCommit(uncommitted)
        return uncommitted
    }

    /// R3.3: switching between two over-cap files refreshes the size label and the
    /// path-derived selection, never leaking the previous file's size or path.
    func testSelectDiffFileTooLargeToTooLargeRefreshesSizeAndPath() async throws {
        try await withMaxDiffFileSizeMB(1) {
            let repo = try TemporaryGitRepository()
            try repo.writeFile("seed.txt", contents: "seed\n")
            try repo.commitAll(message: "initial")
            try writeSizedFile(repo, path: "big-a.bin", megabytes: 2)
            try writeSizedFile(repo, path: "big-b.bin", megabytes: 3)

            let viewModel = RepoViewModel(path: repo.path, name: "repo")
            _ = try await selectUncommitted(viewModel)

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "big-a.bin"), context: .unstaged)
            XCTAssertTrue(viewModel.isFileTooLarge)
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "2.0")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "big-a.bin")

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "big-b.bin"), context: .unstaged)
            XCTAssertTrue(viewModel.isFileTooLarge, "still too large after switching to the second over-cap file")
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "3.0", "size label must reflect the newly selected file (R3.3)")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "big-b.bin", "displayed path must follow the new selection (R3.3)")
            XCTAssertNil(viewModel.selectedDiffVisualContent, "no visual preview should leak into a too-large placeholder")
        }
    }

    /// R3.4: moving from a too-large placeholder to a renderable file shows the
    /// renderable preview in the same selection event, with no stale too-large frame.
    func testSelectDiffFileTooLargeToRenderableRendersPreviewInOneEvent() async throws {
        try await withMaxDiffFileSizeMB(1) {
            let repo = try TemporaryGitRepository()
            try repo.writeFile("seed.txt", contents: "seed\n")
            try repo.commitAll(message: "initial")
            try writeSizedFile(repo, path: "big.bin", megabytes: 2)
            try repo.writeFile("small.txt", contents: "hello world\n")

            let viewModel = RepoViewModel(path: repo.path, name: "repo")
            _ = try await selectUncommitted(viewModel)

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "big.bin"), context: .unstaged)
            XCTAssertTrue(viewModel.isFileTooLarge)
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "2.0")

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "small.txt"), context: .unstaged)
            XCTAssertFalse(viewModel.isFileTooLarge, "too-large state must clear when switching to a renderable file (R3.4)")
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "", "size label must reset for a renderable selection")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "small.txt")
            XCTAssertNil(viewModel.selectedDiffVisualContent, "a text file resolves to the Monaco text preview, not visual content")
            XCTAssertFalse(viewModel.fileDiffContent.isEmpty, "the renderable text diff should be loaded in the same event")
        }
    }

    /// R3.5: moving from a renderable file back to a too-large file binds the placeholder
    /// to the new selection's path/size and never leaks the previous file's content.
    func testSelectDiffFileRenderableToTooLargeBindsPlaceholderToNewSelection() async throws {
        try await withMaxDiffFileSizeMB(1) {
            let repo = try TemporaryGitRepository()
            try repo.writeFile("seed.txt", contents: "seed\n")
            try repo.commitAll(message: "initial")
            try repo.writeFile("small.txt", contents: "hello world\n")
            try writeSizedFile(repo, path: "big.bin", megabytes: 3)

            let viewModel = RepoViewModel(path: repo.path, name: "repo")
            _ = try await selectUncommitted(viewModel)

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "small.txt"), context: .unstaged)
            XCTAssertFalse(viewModel.isFileTooLarge)
            XCTAssertFalse(viewModel.fileDiffContent.isEmpty)
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "small.txt")

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "big.bin"), context: .unstaged)
            XCTAssertTrue(viewModel.isFileTooLarge, "switching to an over-cap file must show the size-limit placeholder (R3.5)")
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "3.0", "placeholder size must bind to the new selection")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "big.bin", "placeholder path must bind to the new selection")
            XCTAssertEqual(viewModel.fileDiffContent, "", "the previous file's diff text must not leak into the placeholder")
            XCTAssertNil(viewModel.selectedDiffVisualContent, "no previous visual content may leak into the placeholder")
            XCTAssertNil(viewModel.parsedDiff)
        }
    }

    /// renderable → renderable: switching between two renderable files swaps the active
    /// preview kind (text → image) with no residual state from the previous file.
    func testSelectDiffFileRenderableToRenderableSwapsPreviewKind() async throws {
        try await withMaxDiffFileSizeMB(1) {
            let repo = try TemporaryGitRepository()
            try repo.writeFile("seed.txt", contents: "seed\n")
            try repo.commitAll(message: "initial")
            try repo.writeFile("small.txt", contents: "hello world\n")
            let imageURL = URL(fileURLWithPath: repo.path).appendingPathComponent("diagram.png")
            try onePixelPNGData.write(to: imageURL)

            let viewModel = RepoViewModel(path: repo.path, name: "repo")
            _ = try await selectUncommitted(viewModel)

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "small.txt"), context: .unstaged)
            XCTAssertFalse(viewModel.isFileTooLarge)
            XCTAssertNil(viewModel.selectedDiffVisualContent, "text file → Monaco text preview (no visual content)")
            XCTAssertFalse(viewModel.fileDiffContent.isEmpty)
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "small.txt")

            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "diagram.png"), context: .unstaged)
            XCTAssertFalse(viewModel.isFileTooLarge)
            XCTAssertEqual(viewModel.selectedDiffVisualContent?.kind, .image, "image file → image visual preview kind")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "diagram.png")
            XCTAssertNil(viewModel.parsedDiff, "no parsed text diff should linger from the previous text file")
        }
    }

    /// R3.6: when a second selection begins before the first selection's load completes,
    /// the late-arriving payload is discarded by the generation token and the final state
    /// matches the most recent selection.
    func testSelectDiffFileRapidReselectionDiscardsStaleLoad() async throws {
        try await withMaxDiffFileSizeMB(1) {
            let repo = try TemporaryGitRepository()
            try repo.writeFile("seed.txt", contents: "seed\n")
            try repo.commitAll(message: "initial")
            try repo.writeFile("small.txt", contents: "hello world\n")
            try writeSizedFile(repo, path: "big.bin", megabytes: 2)

            let viewModel = RepoViewModel(path: repo.path, name: "repo")
            _ = try await selectUncommitted(viewModel)

            // Kick off the renderable selection without awaiting; it suspends at its
            // detached payload load.
            let firstSelection = Task {
                await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "small.txt"), context: .unstaged)
            }
            // Let the first selection run up to its async payload load and suspend.
            await Task.yield()

            // The second selection (an over-cap file) resolves synchronously through the
            // too-large guard, superseding the first selection's generation token.
            await viewModel.selectDiffFile(DiffFile(additions: 0, deletions: 0, path: "big.bin"), context: .unstaged)

            // Allow the first (now-stale) load to finish; its write-back must be discarded.
            await firstSelection.value

            XCTAssertTrue(viewModel.isFileTooLarge, "final state must match the most recent selection (R3.6)")
            XCTAssertEqual(viewModel.fileTooLargeSizeMB, "2.0")
            XCTAssertEqual(viewModel.selectedDiffFile?.path, "big.bin")
            XCTAssertEqual(viewModel.fileDiffContent, "", "the stale renderable load must not populate diff content")
            XCTAssertNil(viewModel.selectedDiffVisualContent, "the stale load must not populate visual content")
        }
    }

    private func makeCommit(hash: String, parentHashes: [String] = [], message: String) -> CommitInfo {        CommitInfo(
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

    // MARK: - performSquashCommits integration (Task 12.1, R4.8, R5.2)

    /// R5.2 + R4.8: dirty tree squash — working directory changes are restored
    /// after stash pop and the success toast matches R4.8 format.
    func testPerformSquashCommitsDirtyTreeRestoresWorkingDirectoryChanges() async throws {
        let repo = try TemporaryGitRepository()

        // Build history: 3 commits (oldest → newest), HEAD at c3.
        try repo.writeFile("file.txt", contents: "line1\n")
        try repo.commitAll(message: "commit1")
        try repo.writeFile("file.txt", contents: "line2\n")
        let c2 = try repo.commitAll(message: "commit2")
        try repo.writeFile("file.txt", contents: "line3\n")
        let c3 = try repo.commitAll(message: "commit3")

        // Dirty the working tree with an untracked file.
        try repo.writeFile("dirty.txt", contents: "uncommitted work\n")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        // Squash c2 and c3 (the top 2 commits). hashes.count = 2 → "Squashed 1 commits into 1".
        await viewModel.performSquashCommits([c3, c2])

        // Working directory changes must be restored after stash pop.
        let restoredContent = try repo.readFile("dirty.txt")
        XCTAssertEqual(restoredContent, "uncommitted work\n",
                       "Auto-stash pop must restore dirty working tree changes")

        // Success toast must follow R4.8 format.
        XCTAssertEqual(viewModel.toastMessage?.title, "Squash Completed")
        XCTAssertEqual(viewModel.toastMessage?.detail, "Squashed 1 commits into 1")
        XCTAssertEqual(viewModel.toastMessage?.style, .success)

        // operationInProgress must be cleared.
        XCTAssertFalse(viewModel.operationInProgress)
    }

    /// R5.1 + R4.8: clean tree squash must not create any residual stash entries.
    func testPerformSquashCommitsCleanTreeLeavesNoResidualStash() async throws {
        let repo = try TemporaryGitRepository()

        try repo.writeFile("a.txt", contents: "a\n")
        try repo.commitAll(message: "commit1")
        try repo.writeFile("a.txt", contents: "b\n")
        let c2 = try repo.commitAll(message: "commit2")
        try repo.writeFile("a.txt", contents: "c\n")
        let c3 = try repo.commitAll(message: "commit3")

        // Ensure working tree is clean.
        let statusOutput = try repo.run(["status", "--porcelain"])
        XCTAssertTrue(statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "Pre-condition: working tree must be clean")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        await viewModel.performSquashCommits([c3, c2])

        // No stash entries must have been created.
        let stashList = try repo.run(["stash", "list"])
        XCTAssertTrue(stashList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "Clean tree squash must leave zero residual stash entries (R5.1)")

        // Success toast must follow R4.8 format.
        XCTAssertEqual(viewModel.toastMessage?.title, "Squash Completed")
        XCTAssertEqual(viewModel.toastMessage?.detail, "Squashed 1 commits into 1")
        XCTAssertEqual(viewModel.toastMessage?.style, .success)
    }

    /// R4.8: success toast detail format matches "|Squash_Set| commits into 1".
    func testPerformSquashCommitsToastDetailMatchesR48Format() async throws {
        let repo = try TemporaryGitRepository()

        // Build history: 5 commits (c1 oldest, c5 HEAD).
        // We squash c2..c5 (4 commits) so |Squash_Set| = 3 → "Squashed 3 commits into 1".
        try repo.writeFile("f.txt", contents: "1\n")
        try repo.commitAll(message: "c1")
        try repo.writeFile("f.txt", contents: "2\n")
        let c2 = try repo.commitAll(message: "c2")
        try repo.writeFile("f.txt", contents: "3\n")
        let c3 = try repo.commitAll(message: "c3")
        try repo.writeFile("f.txt", contents: "4\n")
        let c4 = try repo.commitAll(message: "c4")
        try repo.writeFile("f.txt", contents: "5\n")
        let c5 = try repo.commitAll(message: "c5")

        let viewModel = RepoViewModel(path: repo.path, name: "repo")
        await viewModel.loadAll()

        // Squash 4 commits (c2..c5): hashes.count = 4 → "Squashed 3 commits into 1"
        await viewModel.performSquashCommits([c5, c4, c3, c2])

        XCTAssertEqual(viewModel.toastMessage?.title, "Squash Completed")
        XCTAssertEqual(viewModel.toastMessage?.detail, "Squashed 3 commits into 1",
                       "Toast detail must be 'Squashed N-1 commits into 1' (R4.8)")
    }
}

private func requireGitLFS(file: StaticString = #filePath, line: UInt = #line) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["lfs", "version"]
    process.currentDirectoryURL = FileManager.default.temporaryDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw XCTSkip("git-lfs is not installed in this environment")
    }
}

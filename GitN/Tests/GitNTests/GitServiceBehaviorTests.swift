import XCTest
@testable import GitN

final class GitServiceBehaviorTests: XCTestCase {
    func testFileLogFollowsRenameHistory() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.txt", contents: "one\n")
        let initialHash = try repo.commitAll(message: "initial notes")

        try repo.run(["mv", "notes.txt", "journal.txt"])
        let renameHash = try repo.commitAll(message: "rename notes")

        try repo.appendFile("journal.txt", contents: "two\n")
        let updateHash = try repo.commitAll(message: "update journal")

        let service = GitService(repoPath: repo.path)
        let commits = try await service.fileLog(path: "journal.txt")

        XCTAssertEqual(
            commits.map(\.message),
            ["update journal", "rename notes", "initial notes"]
        )
        XCTAssertEqual(
            commits.map(\.hash),
            [updateHash, renameHash, initialHash]
        )
    }

    func testStatusReportsMixedStagedAndUnstagedChangesForSameFile() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        try repo.writeFile("tracked.txt", contents: "one\ntwo\n")
        try repo.run(["add", "tracked.txt"])
        try repo.appendFile("tracked.txt", contents: "three\n")

        let service = GitService(repoPath: repo.path)
        let statuses = try await service.status()

        XCTAssertEqual(
            statuses.first(where: { $0.path == "tracked.txt" })?.statusCode,
            "MM"
        )
    }

    func testAddToGitignoreAppendsOnSeparateLineWithoutTrailingNewline() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitignore", contents: "build")

        let service = GitService(repoPath: repo.path)
        try await service.addToGitignore(pattern: "DerivedData/")

        XCTAssertEqual(
            try repo.readFile(".gitignore"),
            "build\nDerivedData/\n"
        )
    }

    func testReflogClassifiesCommitCheckoutAndResetEntries() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        try repo.appendFile("file.txt", contents: "two\n")
        try repo.commitAll(message: "second")
        let previousHash = try repo.run(["rev-parse", "HEAD^"])

        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("topic.txt", contents: "topic\n")
        try repo.commitAll(message: "topic work")
        try repo.run(["checkout", "main"])
        try repo.run(["reset", "--hard", previousHash])

        let service = GitService(repoPath: repo.path)
        let entries = try await service.reflog()

        XCTAssertEqual(entries.map(\.index), Array(0..<entries.count))
        XCTAssertTrue(entries.contains(where: { $0.kind == .commit }))
        XCTAssertTrue(entries.contains(where: { $0.kind == .checkout }))
        XCTAssertTrue(entries.contains(where: { $0.kind == .reset }))
    }

    func testCurrentBranchAndDetachedHeadReflectCheckoutState() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        let headHash = try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        let initialBranch = try await service.currentBranch()
        let initialDetached = try await service.isDetachedHead()
        XCTAssertEqual(initialBranch, "main")
        XCTAssertFalse(initialDetached)

        try repo.run(["checkout", headHash])

        let detachedBranch = try await service.currentBranch()
        let detachedHead = try await service.isDetachedHead()
        XCTAssertEqual(detachedBranch, String(headHash.prefix(7)))
        XCTAssertTrue(detachedHead)
    }

    func testStageAndUnstageFileRoundTripStatusCode() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")

        let service = GitService(repoPath: repo.path)

        try await service.stageFile("tracked.txt")
        let stagedStatus = try await service.status().first(where: { $0.path == "tracked.txt" })?.statusCode
        XCTAssertEqual(
            stagedStatus,
            "M "
        )

        try await service.unstageFile("tracked.txt")
        let unstagedStatus = try await service.status().first(where: { $0.path == "tracked.txt" })?.statusCode
        XCTAssertEqual(
            unstagedStatus,
            " M"
        )
    }

    func testDiscardFileChangesKeepsStagedContentAndDropsWorktreeOnlyEdits() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("tracked.txt", contents: "one\ntwo\n")
        try repo.run(["add", "tracked.txt"])
        try repo.appendFile("tracked.txt", contents: "three\n")

        let service = GitService(repoPath: repo.path)
        try await service.discardFileChanges(path: "tracked.txt")
        let statusAfterDiscard = try await service.status().first(where: { $0.path == "tracked.txt" })?.statusCode

        XCTAssertEqual(try repo.readFile("tracked.txt"), "one\ntwo\n")
        XCTAssertEqual(
            statusAfterDiscard,
            "M "
        )
    }

    func testBranchLifecycleCreatesRenamesAndDeletesLocalBranch() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        try await service.createBranch(name: "topic", checkout: false)
        let branchesAfterCreate = try await service.localBranches()

        XCTAssertTrue(branchesAfterCreate.contains(where: { $0.name == "topic" && !$0.isCurrent }))

        try await service.renameBranch(oldName: "topic", newName: "renamed-topic")
        let branchesAfterRename = try await service.localBranches()
        XCTAssertTrue(branchesAfterRename.contains(where: { $0.name == "renamed-topic" }))

        try await service.deleteBranch("renamed-topic")
        let branchesAfterDelete = try await service.localBranches()
        XCTAssertFalse(branchesAfterDelete.contains(where: { $0.name == "renamed-topic" }))
    }

    func testRemoteLifecycleTracksAddRenameSetURLAndDelete() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        try await service.addRemote(name: "origin", url: "https://example.com/repo.git")
        let remotesAfterAdd = try await service.remotes()
        XCTAssertEqual(
            remotesAfterAdd.first(where: { $0.name == "origin" })?.url,
            "https://example.com/repo.git"
        )

        try await service.renameRemote(oldName: "origin", newName: "upstream")
        try await service.setRemoteURL(name: "upstream", url: "git@example.com:team/repo.git")
        let remotesAfterUpdate = try await service.remotes()
        XCTAssertEqual(
            remotesAfterUpdate.first(where: { $0.name == "upstream" })?.url,
            "git@example.com:team/repo.git"
        )

        try await service.deleteRemote(name: "upstream")
        let remotesAfterDelete = try await service.remotes()
        XCTAssertTrue(remotesAfterDelete.isEmpty)
    }

    func testAnnotatedTagExposesMessageAndCommitHash() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        let headHash = try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        try await service.createTag(name: "v1.0.0", at: headHash, message: "Release 1")
        let tags = try await service.tags()
        let tagMessage = try await service.tagMessage(name: "v1.0.0")
        let taggedHash = try await service.tagCommitHash(name: "v1.0.0")

        XCTAssertTrue(tags.contains("v1.0.0"))
        XCTAssertEqual(tagMessage, "Release 1")
        XCTAssertEqual(taggedHash, headHash)
    }

    func testStashSaveAndApplyRoundTripsTrackedAndUntrackedChanges() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")
        try repo.writeFile("scratch.txt", contents: "temp\n")

        let service = GitService(repoPath: repo.path)
        try await service.stashSave(message: "work in progress", includeUntracked: true)
        let savedStashes = try await service.stashes()

        XCTAssertEqual(try repo.readFile("tracked.txt"), "one\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: (repo.path as NSString).appendingPathComponent("scratch.txt")))
        XCTAssertTrue(savedStashes.contains(where: { $0.message.contains("work in progress") }))

        try await service.stashApply(index: 0)
        let stashesAfterApply = try await service.stashes()

        XCTAssertEqual(try repo.readFile("tracked.txt"), "one\ntwo\n")
        XCTAssertEqual(try repo.readFile("scratch.txt"), "temp\n")
        XCTAssertEqual(stashesAfterApply.count, 1)
    }

    func testCompareFileListAndDiffAgainstWorkingTree() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let headHash = try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")

        let service = GitService(repoPath: repo.path)
        let diffFiles = try await service.compareFileList(headHash)
        let diff = try await service.compareFileDiff(headHash, path: "tracked.txt")

        XCTAssertEqual(diffFiles.map(\.path), ["tracked.txt"])
        XCTAssertTrue(diff.contains("+two"))
    }

    func testDiffDetailAndFileDiffHandleRootCommit() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("alpha.txt", contents: "one\ntwo\n")
        try repo.writeFile("beta.txt", contents: "three\n")
        let rootHash = try repo.commitAll(message: "initial import")

        let service = GitService(repoPath: repo.path)
        let diffFiles = try await service.diffDetail(hash: rootHash)
        let alphaDiff = try await service.fileDiff(hash: rootHash, path: "alpha.txt")

        XCTAssertEqual(diffFiles.count, 2)
        XCTAssertEqual(diffFiles.first(where: { $0.path == "alpha.txt" })?.additions, 2)
        XCTAssertEqual(diffFiles.first(where: { $0.path == "alpha.txt" })?.deletions, 0)
        XCTAssertNil(diffFiles.first(where: { $0.path == "alpha.txt" })?.oldPath)
        XCTAssertEqual(diffFiles.first(where: { $0.path == "beta.txt" })?.additions, 1)
        XCTAssertNil(diffFiles.first(where: { $0.path == "beta.txt" })?.oldPath)
        XCTAssertTrue(alphaDiff.contains("+++ b/alpha.txt"))
        XCTAssertTrue(alphaDiff.contains("+one"))
        XCTAssertTrue(alphaDiff.contains("+two"))
    }

    func testDiffDetailPreservesPureRenameMetadataAndPatch() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("old-name.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.run(["mv", "old-name.txt", "new-name.txt"])
        let renameHash = try repo.commitAll(message: "rename file")

        let service = GitService(repoPath: repo.path)
        let diffFiles = try await service.diffDetail(hash: renameHash)
        let renameDiff = try await service.fileDiff(hash: renameHash, path: "new-name.txt")

        XCTAssertEqual(diffFiles.count, 1)
        XCTAssertEqual(diffFiles[0].path, "new-name.txt")
        XCTAssertEqual(diffFiles[0].oldPath, "old-name.txt")
        XCTAssertEqual(diffFiles[0].additions, 0)
        XCTAssertEqual(diffFiles[0].deletions, 0)
        XCTAssertTrue(renameDiff.contains("rename from old-name.txt"))
        XCTAssertTrue(renameDiff.contains("rename to new-name.txt"))
    }

    func testCommittedDiffPreviewReturnsMetadataBeforeLineStats() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("old-name.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.run(["mv", "old-name.txt", "new-name.txt"])
        try repo.appendFile("new-name.txt", contents: "two\n")
        let commitHash = try repo.commitAll(message: "rename and update")

        let service = GitService(repoPath: repo.path)
        let previewFiles = try await service.committedDiffPreview(hash: commitHash)
        let detailedFiles = try await service.diffDetail(hash: commitHash)

        XCTAssertEqual(previewFiles.count, 1)
        XCTAssertEqual(previewFiles[0].path, "new-name.txt")
        XCTAssertEqual(previewFiles[0].oldPath, "old-name.txt")
        XCTAssertEqual(previewFiles[0].additions, 0)
        XCTAssertEqual(previewFiles[0].deletions, 0)

        XCTAssertEqual(detailedFiles.count, 1)
        XCTAssertEqual(detailedFiles[0].path, "new-name.txt")
        XCTAssertEqual(detailedFiles[0].oldPath, "old-name.txt")
        XCTAssertEqual(detailedFiles[0].additions, 1)
        XCTAssertEqual(detailedFiles[0].deletions, 0)
    }
}

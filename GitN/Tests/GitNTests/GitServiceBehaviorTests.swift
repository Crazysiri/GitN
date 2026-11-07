import XCTest
@testable import GitN

final class GitServiceBehaviorTests: XCTestCase {
    private func makeTextConflictRepository() throws -> TemporaryGitRepository {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("conflict.txt", contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("conflict.txt", contents: "topic\n")
        try repo.commitAll(message: "topic change")
        try repo.run(["checkout", "main"])
        try repo.writeFile("conflict.txt", contents: "main\n")
        try repo.commitAll(message: "main change")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))
        return repo
    }

    private func makeDeleteModifyConflictRepository(deleteOnTopic: Bool) throws -> TemporaryGitRepository {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("conflict.txt", contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        if deleteOnTopic {
            try repo.run(["rm", "conflict.txt"])
        } else {
            try repo.writeFile("conflict.txt", contents: "modified\n")
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: repo.url.appendingPathComponent("conflict.txt").path)
        }
        try repo.commitAll(message: "topic change")
        try repo.run(["checkout", "main"])
        if deleteOnTopic {
            try repo.writeFile("conflict.txt", contents: "modified\n")
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: repo.url.appendingPathComponent("conflict.txt").path)
        } else {
            try repo.run(["rm", "conflict.txt"])
        }
        try repo.commitAll(message: "main change")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))
        return repo
    }

    func testConflictSaveRejectsExternalWorktreeEdit() async throws {
        let repo = try makeTextConflictRepository()
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        XCTAssertTrue(session.sides.usesStructuralModel)
        XCTAssertEqual(session.sides.markers.first?.baseRange, 0..<1)
        try repo.writeFile("conflict.txt", contents: "external edit\n")

        do {
            try await service.saveConflictResolution(
                path: "conflict.txt", content: "GitN edit\n", expectedSnapshot: session.snapshot
            )
            XCTFail("External edit should block conflict save")
        } catch ConflictSaveError.sourceChanged {}
        XCTAssertEqual(try repo.readFile("conflict.txt"), "external edit\n")
        XCTAssertFalse(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
    }

    func testConflictSaveRejectsExternalIndexResolution() async throws {
        let repo = try makeTextConflictRepository()
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        try repo.run(["add", "--", "conflict.txt"])
        let externalContent = try repo.readFile("conflict.txt")

        do {
            try await service.saveConflictResolution(
                path: "conflict.txt", content: "GitN edit\n", expectedSnapshot: session.snapshot
            )
            XCTFail("External index change should block conflict save")
        } catch ConflictSaveError.sourceChanged {}
        XCTAssertEqual(try repo.readFile("conflict.txt"), externalContent)
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
    }

    func testConflictSaveStagesUnchangedSession() async throws {
        let repo = try makeTextConflictRepository()
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")

        try await service.saveConflictResolution(
            path: "conflict.txt", content: "resolved\n", expectedSnapshot: session.snapshot
        )

        XCTAssertEqual(try repo.readFile("conflict.txt"), "resolved\n")
        XCTAssertEqual(try repo.run(["show", ":conflict.txt"]), "resolved")
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
    }

    func testConflictSaveCanRetryAfterIndexLockFailure() async throws {
        let repo = try makeTextConflictRepository()
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        let lock = repo.url.appendingPathComponent(".git/index.lock")
        try Data().write(to: lock)
        defer { try? FileManager.default.removeItem(at: lock) }
        var retrySnapshot: ConflictFileSnapshot?

        do {
            try await service.saveConflictResolution(
                path: "conflict.txt", content: "resolved\n", expectedSnapshot: session.snapshot
            )
            XCTFail("Index lock should block staging")
        } catch ConflictSaveError.stageFailed(_, let snapshot) {
            retrySnapshot = snapshot
        }
        XCTAssertEqual(try repo.readFile("conflict.txt"), "resolved\n")
        XCTAssertFalse(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
        try FileManager.default.removeItem(at: lock)

        try await service.saveConflictResolution(
            path: "conflict.txt", content: "resolved\n",
            expectedSnapshot: try XCTUnwrap(retrySnapshot)
        )
        XCTAssertEqual(try repo.run(["show", ":conflict.txt"]), "resolved")
    }

    func testMarkDeletedConflictResolvedRemovesIndexStages() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("deleted.txt", contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.run(["rm", "deleted.txt"])
        try repo.commitAll(message: "delete")
        try repo.run(["checkout", "main"])
        try repo.writeFile("deleted.txt", contents: "modified\n")
        try repo.commitAll(message: "modify")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))
        try FileManager.default.removeItem(at: repo.url.appendingPathComponent("deleted.txt"))

        let service = GitService(repoPath: repo.path)
        try await service.markConflictResolved(path: "deleted.txt")

        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "deleted.txt"]).isEmpty)
        XCTAssertTrue(try repo.run(["ls-files", "--", "deleted.txt"]).isEmpty)
    }

    func testDeleteModifyChoiceStagesDeletionRatherThanEmptyFile() async throws {
        let repo = try makeDeleteModifyConflictRepository(deleteOnTopic: false)
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        XCTAssertNil(session.snapshot.currentOID)
        XCTAssertNotNil(session.snapshot.incomingOID)
        XCTAssertTrue(session.sides.missingCurrentStage)
        XCTAssertFalse(session.sides.missingIncomingStage)

        try await service.resolveDeleteModifyConflict(path: "conflict.txt", choice: .deleted,
            expectedSnapshot: session.snapshot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("conflict.txt").path))
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
        XCTAssertTrue(try repo.run(["ls-files", "--", "conflict.txt"]).isEmpty)
    }

    func testDeleteModifyChoiceKeepsModifiedStageAndExecutableMode() async throws {
        let repo = try makeDeleteModifyConflictRepository(deleteOnTopic: true)
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        XCTAssertNotNil(session.snapshot.currentOID)
        XCTAssertNil(session.snapshot.incomingOID)
        XCTAssertFalse(session.sides.missingCurrentStage)
        XCTAssertTrue(session.sides.missingIncomingStage)

        try await service.resolveDeleteModifyConflict(path: "conflict.txt", choice: .modified,
            expectedSnapshot: session.snapshot)

        XCTAssertEqual(try repo.readFile("conflict.txt"), "modified\n")
        XCTAssertTrue(try repo.run(["ls-files", "-s", "--", "conflict.txt"]).hasPrefix("100755 "))
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
    }

    func testDeleteModifyChoiceCanKeepAncestorAndRejectsStaleSnapshot() async throws {
        let repo = try makeDeleteModifyConflictRepository(deleteOnTopic: true)
        let service = GitService(repoPath: repo.path)
        let session = try await service.loadConflictSession(path: "conflict.txt")
        try repo.writeFile("conflict.txt", contents: "external\n")
        do {
            try await service.resolveDeleteModifyConflict(path: "conflict.txt", choice: .ancestor,
                expectedSnapshot: session.snapshot)
            XCTFail("A changed worktree must block the choice")
        } catch ConflictSaveError.sourceChanged {}
        XCTAssertEqual(try repo.readFile("conflict.txt"), "external\n")

        let fresh = try await service.loadConflictSession(path: "conflict.txt")
        try await service.resolveDeleteModifyConflict(path: "conflict.txt", choice: .ancestor,
            expectedSnapshot: fresh.snapshot)
        XCTAssertEqual(try repo.readFile("conflict.txt"), "base\n")
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", "conflict.txt"]).isEmpty)
    }

    func testBinaryDeleteModifyConflictCanKeepModifiedBlobWithoutTextDecoding() async throws {
        let repo = try TemporaryGitRepository()
        let path = "conflict.bin"
        let fileURL = repo.url.appendingPathComponent(path)
        let modified = Data([0x00, 0xff, 0x01, 0x80])
        try Data([0x00, 0x01]).write(to: fileURL)
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.run(["rm", path])
        try repo.commitAll(message: "delete")
        try repo.run(["checkout", "main"])
        try modified.write(to: fileURL)
        try repo.commitAll(message: "binary modify")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let service = GitService(repoPath: repo.path)
        do {
            _ = try await service.loadConflictSession(path: path)
            XCTFail("Binary conflict should require the non-text resolution path")
        } catch {}
        let snapshot = try await service.conflictFileSnapshot(path: path)
        XCTAssertNotNil(snapshot.ancestorOID)
        XCTAssertNotNil(snapshot.currentOID)
        XCTAssertNil(snapshot.incomingOID)

        try await service.resolveDeleteModifyConflict(path: path, choice: .modified,
            expectedSnapshot: snapshot)
        XCTAssertEqual(try Data(contentsOf: fileURL), modified)
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", path]).isEmpty)
    }

    func testDeleteModifyChoicePreservesBrokenSymbolicLink() async throws {
        let repo = try TemporaryGitRepository()
        let path = "link"
        let url = repo.url.appendingPathComponent(path)
        try repo.writeFile(path, contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.run(["rm", path])
        try repo.commitAll(message: "delete")
        try repo.run(["checkout", "main"])
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "missing-target")
        try repo.commitAll(message: "symlink modify")
        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let service = GitService(repoPath: repo.path)
        let snapshot = try await service.conflictFileSnapshot(path: path)
        XCTAssertTrue(snapshot.workingTreeIsSymlink)
        try await service.resolveDeleteModifyConflict(path: path, choice: .modified,
            expectedSnapshot: snapshot)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), "missing-target")
        XCTAssertTrue(try repo.run(["ls-files", "-s", "--", path]).hasPrefix("120000 "))
        XCTAssertTrue(try repo.run(["ls-files", "-u", "--", path]).isEmpty)
    }

    func testLinkedWorktreeReadsMergeAndRebaseMetadata() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("conflict.txt", contents: "base\n")
        try repo.commitAll(message: "base")
        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("conflict.txt", contents: "topic\n")
        try repo.commitAll(message: "topic change")
        try repo.run(["checkout", "main"])

        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitN-conflict-worktree-\(UUID().uuidString)")
        try repo.run(["worktree", "add", "-b", "linked", worktree.path, "main"])
        defer { _ = try? repo.run(["worktree", "remove", "--force", worktree.path]) }
        try "linked\n".write(
            to: worktree.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8
        )
        try repo.run(["-C", worktree.path, "add", "conflict.txt"])
        try repo.run(["-C", worktree.path, "commit", "-m", "linked change"])

        XCTAssertThrowsError(try repo.run(["-C", worktree.path, "merge", "topic"]))
        let service = GitService(repoPath: worktree.path)
        let merge = try await service.mergeConflictState()
        XCTAssertEqual(merge?.sourceBranch, "topic")
        XCTAssertTrue(merge?.conflictedFiles.contains(where: { $0.path == "conflict.txt" }) == true)
        let mergeMessage = await service.mergeCommitMessage()
        XCTAssertFalse(mergeMessage.isEmpty)

        try repo.run(["-C", worktree.path, "merge", "--abort"])
        XCTAssertThrowsError(try repo.run(["-C", worktree.path, "rebase", "topic"]))
        let rebase = try await service.rebaseState()
        XCTAssertNotNil(rebase)
        XCTAssertEqual(rebase?.sourceBranch, "linked")
        let rebaseMessage = await service.rebaseCommitMessage()
        XCTAssertFalse(rebaseMessage.isEmpty)
    }

    func testGitLFSSupportDetectsRootAndNestedGitattributes() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitattributes", contents: "*.psd filter=lfs diff=lfs merge=lfs -text\n")
        try repo.writeFile("Assets/.gitattributes", contents: "*.bin filter=lfs diff=lfs merge=lfs -text\n")

        XCTAssertTrue(GitLFSSupport.repositoryUsesLFS(at: repo.url))
    }

    func testGitLFSSupportIgnoresNonLFSGitattributes() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitattributes", contents: "*.txt text eol=lf\n# *.bin filter=lfs\n")

        XCTAssertFalse(GitLFSSupport.repositoryUsesLFS(at: repo.url))
    }

    func testGitLFSSupportResolvesLocalObjectBeforeSmudgeFallback() throws {
        let repo = try TemporaryGitRepository()
        let oid = String(repeating: "a", count: 64)
        let payload = Data("local-lfs-object".utf8)
        let pointer = Data("""
        version https://git-lfs.github.com/spec/v1
        oid sha256:\(oid)
        size \(payload.count)
        """.utf8)
        let objectURL = repo.url
            .appendingPathComponent(".git/lfs/objects/aa/aa", isDirectory: true)
            .appendingPathComponent(oid)

        try FileManager.default.createDirectory(
            at: objectURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: objectURL)

        let support = GitLFSSupport(repoPath: repo.path)
        let resolved = support.resolveDataIfNeeded(pointer, path: "Assets/image.png")

        XCTAssertEqual(resolved.data, payload)
        XCTAssertTrue(resolved.isLFSPointer)
        XCTAssertTrue(resolved.wasResolved)
    }

    func testGitLFSSupportParsesPointerInfo() throws {
        let payload = Data("""
        version https://git-lfs.github.com/spec/v1
        oid sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        size 42
        """.utf8)

        let pointer = try XCTUnwrap(GitLFSSupport.pointerInfo(for: payload))

        XCTAssertEqual(pointer.oid, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        XCTAssertEqual(pointer.size, 42)
    }

    func testLFSTrackedPathsReturnsOnlyPathsWithFilterLFS() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitattributes", contents: "*.png filter=lfs diff=lfs merge=lfs -text\n")
        try repo.writeFile("icon.png", contents: "image\n")
        try repo.writeFile("notes.txt", contents: "text\n")
        try repo.commitAll(message: "attrs")

        let service = GitService(repoPath: repo.path)
        let tracked = try await service.lfsTrackedPaths(paths: ["icon.png", "notes.txt"])

        XCTAssertEqual(tracked, ["icon.png"])
    }

    func testPushUploadsLFSObjectsWithoutPrePushHook() async throws {
        try requireGitLFS()

        let remoteURL = try makeBareRemoteRepository()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let repo = try TemporaryGitRepository()
        try repo.run(["lfs", "install", "--local"])
        try repo.run(["lfs", "track", "*.bin"])
        try repo.writeFile("asset.bin", contents: String(repeating: "A", count: 4096))
        try repo.commitAll(message: "track binary")
        try repo.run(["remote", "add", "origin", remoteURL.path])

        let prePushHookURL = repo.url.appendingPathComponent(".git/hooks/pre-push")
        try? FileManager.default.removeItem(at: prePushHookURL)

        let service = GitService(repoPath: repo.path)
        try await service.push()

        let cloneURL = FileManager.default.temporaryDirectory.appendingPathComponent("GitNTests-lfs-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cloneURL) }
        try gitRun(["clone", remoteURL.path, cloneURL.path], at: FileManager.default.temporaryDirectory)
        try gitRun(["lfs", "install", "--local"], at: cloneURL)
        try gitRun(["lfs", "pull"], at: cloneURL)
        let clonedAsset = try String(contentsOf: cloneURL.appendingPathComponent("asset.bin"), encoding: .utf8)
        XCTAssertEqual(clonedAsset, String(repeating: "A", count: 4096))
    }

    func testPullHydratesLFSObjectsWhenSmudgeIsDisabled() async throws {
        try requireGitLFS()

        let remoteURL = try makeBareRemoteRepository()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let sourceRepo = try TemporaryGitRepository()
        try sourceRepo.run(["lfs", "install", "--local"])
        try sourceRepo.run(["lfs", "track", "*.bin"])
        try sourceRepo.writeFile("asset.bin", contents: "v1-" + String(repeating: "A", count: 2048))
        try sourceRepo.commitAll(message: "initial asset")
        try sourceRepo.run(["remote", "add", "origin", remoteURL.path])
        try sourceRepo.run(["push", "-u", "origin", "main"])

        let cloneURL = FileManager.default.temporaryDirectory.appendingPathComponent("GitNTests-lfs-pull-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cloneURL) }
        try gitRun(["clone", remoteURL.path, cloneURL.path], at: FileManager.default.temporaryDirectory)
        try gitRun(["lfs", "install", "--local", "--skip-smudge"], at: cloneURL)

        try sourceRepo.writeFile("asset.bin", contents: "v2-" + String(repeating: "B", count: 2048))
        try sourceRepo.commitAll(message: "update asset")
        try sourceRepo.run(["push", "origin", "main"])

        let service = GitService(repoPath: cloneURL.path)
        try await service.pull()

        let updatedAsset = try String(contentsOf: cloneURL.appendingPathComponent("asset.bin"), encoding: .utf8)
        XCTAssertEqual(updatedAsset, "v2-" + String(repeating: "B", count: 2048))
    }

    func testReadConflictSidesUsesResolvedLFSTextInsteadOfPointerText() async throws {
        try requireGitLFS()

        let repo = try TemporaryGitRepository()
        try repo.run(["lfs", "install", "--local"])
        try repo.run(["lfs", "track", "*.txt"])
        try repo.writeFile("notes.txt", contents: "base\n")
        try repo.commitAll(message: "base")

        try repo.run(["checkout", "-b", "topic"])
        try repo.writeFile("notes.txt", contents: "ours\n")
        try repo.commitAll(message: "ours")

        try repo.run(["checkout", "main"])
        try repo.writeFile("notes.txt", contents: "theirs\n")
        try repo.commitAll(message: "theirs")

        XCTAssertThrowsError(try repo.run(["merge", "topic"]))

        let service = GitService(repoPath: repo.path)
        let sides = try await service.readConflictSides(path: "notes.txt")

        XCTAssertEqual(sides.baseLines, ["base", ""])
        XCTAssertEqual(sides.oursLines, ["theirs", ""])
        XCTAssertEqual(sides.theirsLines, ["ours", ""])
        XCTAssertFalse(sides.mergedText.contains("version https://git-lfs.github.com/spec/v1"))
    }

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

    func testFileLogEntriesResolveHistoricalPathAcrossRename() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.txt", contents: "one\n")
        _ = try repo.commitAll(message: "initial notes")

        try repo.run(["mv", "notes.txt", "journal.txt"])
        _ = try repo.commitAll(message: "rename notes")

        try repo.appendFile("journal.txt", contents: "two\n")
        _ = try repo.commitAll(message: "update journal")

        let service = GitService(repoPath: repo.path)
        let entries = try await service.fileLogEntries(path: "journal.txt")

        XCTAssertEqual(
            entries.map(\.pathAtCommit),
            ["journal.txt", "journal.txt", "notes.txt"]
        )
    }

    func testDecodedFileContentIfExistsDiscoversRepositoryFromSubdirectory() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("app/Manager/AppClipLock.swift", contents: "lock\n")
        let hash = try repo.commitAll(message: "add lock")

        let service = GitService(repoPath: repo.path + "/app")
        let content = try await service.decodedFileContentIfExists(
            atCommit: hash,
            path: "app/Manager/AppClipLock.swift"
        )
        let missing = try await service.decodedFileContentIfExists(
            atCommit: hash,
            path: "Manager/AppClipLock.swift"
        )

        XCTAssertEqual(content?.text, "lock\n")
        XCTAssertNil(missing)
    }

    func testFileLogDiffFallsBackWhenFollowPatchOnlyContainsRenameMetadata() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.txt", contents: "one\n")
        _ = try repo.commitAll(message: "initial notes")

        try repo.run(["mv", "notes.txt", "journal.txt"])
        let renameHash = try repo.commitAll(message: "rename notes")

        let service = GitService(repoPath: repo.path)
        let diff = try await service.fileLogDiff(hash: renameHash, path: "journal.txt")

        XCTAssertTrue(diff.contains("@@ -0,0 +1 @@"))
        XCTAssertTrue(diff.contains("+++ b/journal.txt"))
        XCTAssertTrue(diff.contains("+one"))
    }

    func testFileLogCanBeAnchoredToSpecificRevision() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        let initialHash = try repo.commitAll(message: "initial")

        try repo.run(["checkout", "-b", "topic"])
        try repo.appendFile("tracked.txt", contents: "two\n")
        let topicHash = try repo.commitAll(message: "topic change")

        try repo.run(["checkout", "main"])
        try repo.writeFile("other.txt", contents: "main\n")
        _ = try repo.commitAll(message: "main change")

        let service = GitService(repoPath: repo.path)
        let defaultHistory = try await service.fileLog(path: "tracked.txt")
        let anchoredHistory = try await service.fileLog(path: "tracked.txt", revision: topicHash)

        XCTAssertEqual(defaultHistory.map(\.hash), [initialHash])
        XCTAssertEqual(anchoredHistory.map(\.hash), [topicHash, initialHash])
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

    func testDeleteRemoteBranchTreatsMissingRemoteRefAsSuccess() async throws {
        let remoteURL = try makeBareRemoteRepository()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.run(["remote", "add", "origin", remoteURL.path])
        try repo.run(["checkout", "-b", "topic"])
        try repo.appendFile("file.txt", contents: "two\n")
        try repo.commitAll(message: "topic")
        try repo.run(["push", "-u", "origin", "topic"])

        let service = GitService(repoPath: repo.path)

        let firstDeleteResult = try await service.deleteRemoteBranch(remote: "origin", branch: "topic")
        XCTAssertEqual(firstDeleteResult, .deleted)
        XCTAssertEqual(try gitOutput(at: repo.url, ["ls-remote", "--heads", "origin", "topic"]), "")
        let remoteBranchesAfterFirstDelete = try await service.remoteBranches()
        XCTAssertFalse(remoteBranchesAfterFirstDelete.contains(where: { $0.name == "origin/topic" }))

        let secondDeleteResult = try await service.deleteRemoteBranch(remote: "origin", branch: "topic")
        XCTAssertEqual(secondDeleteResult, .alreadyMissing)
        let remoteBranchesAfterSecondDelete = try await service.remoteBranches()
        XCTAssertFalse(remoteBranchesAfterSecondDelete.contains(where: { $0.name == "origin/topic" }))
    }

    func testCommitInvalidatesCachedRefMap() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        _ = try await service.commitLog(maxCount: 10)

        try repo.appendFile("file.txt", contents: "two\n")
        try await service.stageFile("file.txt")
        try await service.commit(message: "second")

        let commits = try await service.commitLog(maxCount: 10)
        XCTAssertEqual(commits.first?.message, "second")
        let refOwner = try XCTUnwrap(commits.first(where: { $0.refs.contains(where: { $0.contains("main") }) }))
        XCTAssertEqual(refOwner.hash, commits.first?.hash)
    }

    func testCommitAmendInvalidatesCachedRefMap() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("file.txt", contents: "two\n")
        try repo.commitAll(message: "second")

        let service = GitService(repoPath: repo.path)
        _ = try await service.commitLog(maxCount: 10)

        try repo.appendFile("file.txt", contents: "three\n")
        try await service.stageFile("file.txt")
        try await service.commitAmend(message: "second amended")

        let commits = try await service.commitLog(maxCount: 10)
        XCTAssertEqual(commits.first?.message, "second amended")
        let refOwner = try XCTUnwrap(commits.first(where: { $0.refs.contains(where: { $0.contains("main") }) }))
        XCTAssertEqual(refOwner.hash, commits.first?.hash)
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
        let savedOID = try await service.stashSave(message: "work in progress", includeUntracked: true)
        let savedStashes = try await service.stashes()

        XCTAssertEqual(try repo.readFile("tracked.txt"), "one\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: (repo.path as NSString).appendingPathComponent("scratch.txt")))
        XCTAssertTrue(savedStashes.contains(where: { $0.message.contains("work in progress") }))
        XCTAssertEqual(savedStashes.first?.oid, savedOID)

        try await service.stashApply(oid: savedOID)
        let stashesAfterApply = try await service.stashes()

        XCTAssertEqual(try repo.readFile("tracked.txt"), "one\ntwo\n")
        XCTAssertEqual(try repo.readFile("scratch.txt"), "temp\n")
        XCTAssertEqual(stashesAfterApply.count, 1)
    }

    func testStashOIDSurvivesIndexShiftForReadApplyAndDrop() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "base\n")
        try repo.commitAll(message: "initial")
        let service = GitService(repoPath: repo.path)

        try repo.writeFile("tracked.txt", contents: "first\n")
        let firstOID = try await service.stashSave(message: "first")
        try repo.writeFile("tracked.txt", contents: "second\n")
        let secondOID = try await service.stashSave(message: "second")

        let stashes = try await service.stashes()
        XCTAssertEqual(stashes.map(\.oid), [secondOID, firstOID])
        XCTAssertEqual(stashes.last?.index, "stash@{1}")
        let firstFiles = try await service.stashDiffFiles(firstOID)
        XCTAssertEqual(firstFiles.map(\.path), ["tracked.txt"])
        let firstDiff = try await service.stashFileDiff(firstOID, path: "tracked.txt")
        XCTAssertTrue(firstDiff.contains("+first"))
        XCTAssertFalse(firstDiff.contains("+second"))

        try await service.stashApply(oid: firstOID)
        XCTAssertEqual(try repo.readFile("tracked.txt"), "first\n")
        try await service.stashDrop(oid: firstOID)
        let afterDrop = try await service.stashes()
        XCTAssertEqual(afterDrop.map(\.oid), [secondOID])

        do {
            try await service.stashDrop(oid: firstOID)
            XCTFail("A missing OID must not drop the remaining stash")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no longer exists"))
        }
        let afterRejectedDrop = try await service.stashes()
        XCTAssertEqual(afterRejectedDrop.map(\.oid), [secondOID])
    }

    func testStashPopTargetsOIDAfterIndexShift() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "base\n")
        try repo.commitAll(message: "initial")
        let service = GitService(repoPath: repo.path)

        try repo.writeFile("tracked.txt", contents: "first\n")
        let firstOID = try await service.stashSave(message: "first")
        try repo.writeFile("tracked.txt", contents: "second\n")
        let secondOID = try await service.stashSave(message: "second")

        try await service.stashPop(oid: firstOID)
        XCTAssertEqual(try repo.readFile("tracked.txt"), "first\n")
        let remaining = try await service.stashes()
        XCTAssertEqual(remaining.map(\.oid), [secondOID])
    }

    func testStashApplyWithUnrelatedStagedChangesPreservesBothSides() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("saved.md", contents: "base saved\n")
        try repo.writeFile("existing.md", contents: "base existing\n")
        try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        try repo.writeFile("saved.md", contents: "stashed saved\n")
        try repo.run(["add", "saved.md"])
        try repo.writeFile("untracked.md", contents: "stashed untracked\n")
        let oid = try await service.stashSave(message: "saved", includeUntracked: true)

        try repo.writeFile("existing.md", contents: "currently staged\n")
        try repo.run(["add", "existing.md"])
        try await service.stashApply(oid: oid)

        XCTAssertEqual(try repo.readFile("saved.md"), "stashed saved\n")
        XCTAssertEqual(try repo.readFile("untracked.md"), "stashed untracked\n")
        XCTAssertEqual(try repo.run(["show", ":existing.md"]), "currently staged")
        let remaining = try await service.stashes()
        XCTAssertEqual(remaining.map(\.oid), [oid])
    }

    func testStashPopWithUnrelatedStagedChangesDropsOnlyAppliedOID() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("saved.md", contents: "base saved\n")
        try repo.writeFile("existing.md", contents: "base existing\n")
        try repo.commitAll(message: "initial")

        let service = GitService(repoPath: repo.path)
        try repo.writeFile("saved.md", contents: "stashed saved\n")
        let oid = try await service.stashSave(message: "saved")
        try repo.writeFile("existing.md", contents: "currently staged\n")
        try repo.run(["add", "existing.md"])

        try await service.stashPop(oid: oid)

        XCTAssertEqual(try repo.readFile("saved.md"), "stashed saved\n")
        XCTAssertEqual(try repo.run(["show", ":existing.md"]), "currently staged")
        let remaining = try await service.stashes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStashPopConflictRetainsEntry() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("notes.md", contents: "base\n")
        try repo.commitAll(message: "initial")
        let service = GitService(repoPath: repo.path)

        try repo.writeFile("notes.md", contents: "stashed\n")
        let oid = try await service.stashSave(message: "saved")
        try repo.writeFile("notes.md", contents: "current edits\n")

        do {
            try await service.stashPop(oid: oid)
            XCTFail("Pop must reject overlapping working-tree edits")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("notes.md"))
        }
        XCTAssertEqual(try repo.readFile("notes.md"), "current edits\n")
        let remaining = try await service.stashes()
        XCTAssertEqual(remaining.map(\.oid), [oid])
    }

    func testStashPathDecodedContentReadsUntrackedFromStashTree() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("only_in_stash.txt", contents: "hidden\n")

        let service = GitService(repoPath: repo.path)
        try await service.stashSave(message: "wip", includeUntracked: true)
        let stashes = try await service.stashes()
        let ref = try XCTUnwrap(stashes.first?.index)

        let decoded = await service.stashPathDecodedContent(stashRef: ref, path: "only_in_stash.txt")
        XCTAssertEqual(decoded?.text, "hidden\n")
    }

    func testStashDiffFilesPreservesFullLongPathForDiffLoading() async throws {
        let repo = try TemporaryGitRepository()
        let longPath = "very/long/nested/path/for/stash/diff/loading/that/used/to/get/truncated/in/stat/output/MGLoginController+Context.swift"
        try repo.writeFile(longPath, contents: "base\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile(longPath, contents: "token\n")

        let service = GitService(repoPath: repo.path)
        try await service.stashSave(message: "wip", includeUntracked: true)
        let stashes = try await service.stashes()
        let ref = try XCTUnwrap(stashes.first?.index)

        let diffFiles = try await service.stashDiffFiles(ref)
        XCTAssertEqual(diffFiles.map(\.path), [longPath])

        let diff = try await service.stashFileDiff(ref, path: longPath)
        XCTAssertTrue(diff.contains("+++ b/\(longPath)"))
        XCTAssertTrue(diff.contains("+token"))
    }

    func testStashPathsAndUTF16MarkdownUseRawGitBytes() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("中文.md", contents: "旧内容\n")
        try repo.writeFile("old.md", contents: "rename me\n")
        try repo.writeFile("deleted.md", contents: "gone\n")
        try repo.commitAll(message: "initial")
        try repo.writeFile("中文.md", contents: "新内容\n")
        try repo.run(["mv", "old.md", "新名.md"])
        try repo.run(["rm", "deleted.md"])
        try repo.writeFile("tab\tname.md", contents: "tab content\n")
        try repo.writeFile("line\nbreak.md", contents: "newline content\n")
        let utf16 = try XCTUnwrap("编码内容\n".data(using: .utf16))
        try utf16.write(to: repo.url.appendingPathComponent("编码.md"))

        let service = GitService(repoPath: repo.path)
        try await service.stashSave(message: "unicode files", includeUntracked: true)
        let stashes = try await service.stashes()
        let ref = try XCTUnwrap(stashes.first?.index)
        let files = try await service.stashDiffFiles(ref)
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })

        XCTAssertEqual(Set(byPath.keys), Set(["中文.md", "新名.md", "deleted.md", "tab\tname.md", "line\nbreak.md", "编码.md"]))
        XCTAssertEqual(byPath["新名.md"]?.oldPath, "old.md")
        XCTAssertEqual(byPath["新名.md"]?.changeKind, .renamed)
        XCTAssertEqual(byPath["deleted.md"]?.changeKind, .deleted)
        let diff = try await service.stashFileDiff(ref, path: "中文.md")
        XCTAssertTrue(diff.contains("+新内容"))
        let chinese = await service.stashPathDecodedContent(stashRef: ref, path: "中文.md")
        XCTAssertEqual(chinese?.text, "新内容\n")
        let tab = await service.stashPathDecodedContent(stashRef: ref, path: "tab\tname.md")
        XCTAssertEqual(tab?.text, "tab content\n")
        let newline = await service.stashPathDecodedContent(stashRef: ref, path: "line\nbreak.md")
        XCTAssertEqual(newline?.text, "newline content\n")
        let encoded = await service.stashPathDecodedContent(stashRef: ref, path: "编码.md")
        XCTAssertEqual(encoded?.text, "编码内容\n")
        XCTAssertEqual(encoded?.encodingName, "UTF-16")
        let encodedDiff = try await service.stashFileDiff(ref, path: "编码.md")
        XCTAssertTrue(encodedDiff.contains("+编码内容"))

        let oid = try XCTUnwrap(stashes.first?.oid)
        let modified = try await service.stashFileVersions(stashOID: oid, path: "中文.md", changeKind: .modified)
        XCTAssertEqual(modified.oldContent?.text, "旧内容\n")
        XCTAssertEqual(modified.newContent?.text, "新内容\n")

        let deleted = try await service.stashFileVersions(stashOID: oid, path: "deleted.md", changeKind: .deleted)
        XCTAssertEqual(deleted.oldContent?.text, "gone\n")
        XCTAssertNil(deleted.newData)
        XCTAssertNil(deleted.newContent)

        let renamed = try await service.stashFileVersions(
            stashOID: oid, path: "新名.md", oldPath: "old.md", changeKind: .renamed
        )
        XCTAssertEqual(renamed.oldContent?.text, "rename me\n")
        XCTAssertEqual(renamed.newContent?.text, "rename me\n")

        let untracked = try await service.stashFileVersions(
            stashOID: oid, path: "编码.md", changeKind: .untracked
        )
        XCTAssertNil(untracked.oldData)
        XCTAssertEqual(untracked.newContent?.text, "编码内容\n")
        XCTAssertEqual(untracked.newContent?.encodingName, "UTF-16")
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

    // MARK: - Binary image change kind

    func testModifiedBinaryImageChangeKindIsModified() async throws {
        let repo = try TemporaryGitRepository()

        // 1x1 transparent PNG
        let pngV1 = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN6kAAAAASUVORK5CYII=")!
        // 1x1 red PNG (different binary content)
        let pngV2 = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==")!

        let pngURL = URL(fileURLWithPath: repo.path).appendingPathComponent("icon.png")
        try pngV1.write(to: pngURL)
        try repo.commitAll(message: "add icon")

        try pngV2.write(to: pngURL)
        let modifyHash = try repo.commitAll(message: "update icon")

        let service = GitService(repoPath: repo.path)
        let files = try await service.committedDiffPreview(hash: modifyHash)

        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.path, "icon.png")
        XCTAssertEqual(file.changeKind, .modified,
            "A PNG replaced with different PNG content must be .modified, not .deleted or .unknown")
        XCTAssertNil(file.oldPath,
            "A same-path binary modification is not a rename and must have no oldPath")
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

    // MARK: - Squash commits

    func testSquashTwoCommitsProducesOneCommit() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        try repo.commitAll(message: "first")

        try repo.appendFile("a.txt", contents: "two\n")
        let olderHash = try repo.commitAll(message: "second")

        try repo.appendFile("a.txt", contents: "three\n")
        let newerHash = try repo.commitAll(message: "third")

        let service = GitService(repoPath: repo.path)
        // hashes are newest-first as the UI passes them
        try await service.squashCommits([newerHash, olderHash])

        let log = try repo.run(["log", "--oneline"])
        let lines = log.split(separator: "\n")
        // two commits squashed into one: only "first" + the squash result remain
        XCTAssertEqual(lines.count, 2, "Expected 2 commits after squash, got: \(log)")
    }

    func testSquashPreservesFileContents() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        try repo.commitAll(message: "base")

        try repo.appendFile("a.txt", contents: "two\n")
        let olderHash = try repo.commitAll(message: "add two")

        try repo.appendFile("a.txt", contents: "three\n")
        let newerHash = try repo.commitAll(message: "add three")

        let service = GitService(repoPath: repo.path)
        try await service.squashCommits([newerHash, olderHash])

        let contents = try repo.readFile("a.txt")
        XCTAssertEqual(contents, "one\ntwo\nthree\n")
    }

    func testSquashNormalizesOldestToNewestInputOrder() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        try repo.commitAll(message: "base")

        try repo.appendFile("a.txt", contents: "two\n")
        let olderHash = try repo.commitAll(message: "add two")

        try repo.appendFile("a.txt", contents: "three\n")
        let newerHash = try repo.commitAll(message: "add three")

        let service = GitService(repoPath: repo.path)
        try await service.squashCommits([olderHash, newerHash])

        let log = try repo.run(["log", "--oneline"])
        let lines = log.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "Expected 2 commits after squash, got: \(log)")

        let contents = try repo.readFile("a.txt")
        XCTAssertEqual(contents, "one\ntwo\nthree\n")
    }

    func testSquashWithFewerThanTwoHashesThrows() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "x\n")
        let hash = try repo.commitAll(message: "only")

        let service = GitService(repoPath: repo.path)
        do {
            try await service.squashCommits([hash])
            XCTFail("Expected squashCommits to throw for a single commit")
        } catch {
            // expected
        }
    }

    // MARK: - Non-contiguous squash (Task 10.1)

    /// R4.4, R4.5, R4.9: Non-contiguous squash {2, 5} out of commits 1..6 (HEAD = 6).
    /// Commits 2 and 5 are squashed into commit 2's position; commits 1, 3, 4, 6 are preserved
    /// in their original relative order.
    func testSquashNonContiguousCommitsTwoAndFiveOutOfSix() async throws {
        let repo = try TemporaryGitRepository()

        // Create commits 1..6 each touching an independent file to avoid rebase conflicts
        // when non-contiguous commits are reordered.
        try repo.writeFile("file1.txt", contents: "content 1\n")
        try repo.commitAll(message: "commit 1")

        try repo.writeFile("file2.txt", contents: "content 2\n")
        let hash2 = try repo.commitAll(message: "commit 2")

        try repo.writeFile("file3.txt", contents: "content 3\n")
        try repo.commitAll(message: "commit 3")

        try repo.writeFile("file4.txt", contents: "content 4\n")
        try repo.commitAll(message: "commit 4")

        try repo.writeFile("file5.txt", contents: "content 5\n")
        let hash5 = try repo.commitAll(message: "commit 5")

        try repo.writeFile("file6.txt", contents: "content 6\n")
        try repo.commitAll(message: "commit 6")

        let service = GitService(repoPath: repo.path)

        // Pass hashes in any order — implementation must handle it
        try await service.squashCommits([hash5, hash2])

        // After squash: commits 2 and 5 merged → history should have 5 commits (was 6)
        let logLines = try repo.run(["log", "--oneline"])
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        XCTAssertEqual(logLines.count, 5,
            "Expected 5 commits after squashing {2,5} out of 6, got: \(logLines)")

        // The messages of non-squashed commits must be preserved in original relative order.
        let allMessages = logLines.joined(separator: "\n")
        XCTAssertTrue(allMessages.contains("commit 6"), "commit 6 must survive squash")
        XCTAssertTrue(allMessages.contains("commit 4"), "commit 4 must survive squash")
        XCTAssertTrue(allMessages.contains("commit 3"), "commit 3 must survive squash")
        XCTAssertTrue(allMessages.contains("commit 1"), "commit 1 must survive squash")

        // The squashed commit's message must contain at least commit 2's message
        XCTAssertTrue(allMessages.contains("commit 2"),
            "The squashed commit message must contain 'commit 2'")

        // All files from all 6 original commits must still be present
        for i in 1...6 {
            XCTAssertEqual(
                try repo.readFile("file\(i).txt"),
                "content \(i)\n",
                "file\(i).txt must have its original content after squash"
            )
        }
    }

    /// R4.5: Passing a clearly unreachable hash must throw without spawning rebase.
    func testSquashRejectsUnreachableHash() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "one\n")
        let realHash = try repo.commitAll(message: "initial")
        try repo.appendFile("a.txt", contents: "two\n")
        let realHash2 = try repo.commitAll(message: "second")
        _ = realHash2

        let fakeHash = "deadbeef1234deadbeef1234deadbeef12345678"
        let service = GitService(repoPath: repo.path)

        do {
            try await service.squashCommits([realHash, fakeHash])
            XCTFail("Expected squashCommits to throw when an unreachable hash is supplied")
        } catch {
            // Must throw without spawning rebase — we verify the repo state is unchanged
            let logLines = try repo.run(["log", "--oneline"])
                .split(separator: "\n")
                .filter { !$0.isEmpty }
            XCTAssertEqual(logLines.count, 2,
                "Repo history must be unmodified after unreachable-hash rejection; got: \(logLines)")
        }
    }

    /// R4.5: Passing a single (deduplicated) hash must throw before spawning rebase.
    func testSquashRejectsSingleDistinctHash() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "x\n")
        let hash = try repo.commitAll(message: "only commit")

        let service = GitService(repoPath: repo.path)
        do {
            // Passing the same hash twice — deduplication should leave only 1
            try await service.squashCommits([hash, hash])
            XCTFail("Expected squashCommits to throw for fewer than 2 distinct commits")
        } catch {
            // expected — verify history untouched
            let logLines = try repo.run(["log", "--oneline"])
                .split(separator: "\n")
                .filter { !$0.isEmpty }
            XCTAssertEqual(logLines.count, 1)
        }
    }

    func testStageFilesThrowsWhenIndexLockFilePresent() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("tracked.txt", contents: "one\n")
        try repo.commitAll(message: "initial")
        try repo.appendFile("tracked.txt", contents: "two\n")

        let lockURL = repo.url.appendingPathComponent(".git/index.lock")
        try "locked".write(to: lockURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lockURL) }

        let service = GitService(repoPath: repo.path)
        do {
            try await service.stageFiles(["tracked.txt"])
            XCTFail("Expected stageFiles to fail when index is locked")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty, "expected a non-empty error from libgit2")
        }
    }

    private func makeBareRemoteRepository() throws -> URL {
        let remoteURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GitNRemote-\(UUID().uuidString).git",
            isDirectory: true
        )
        _ = try gitOutput(
            at: FileManager.default.temporaryDirectory,
            ["init", "--bare", remoteURL.path]
        )
        return remoteURL
    }

    @discardableResult
    private func gitOutput(at workingDirectory: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData + errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }

        return output
    }
}

private func requireGitLFS() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["lfs", "version"]
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    process.environment = GitCLI.enrichedEnvironment()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else {
        throw XCTSkip("git-lfs is not installed in this environment")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw XCTSkip("git-lfs is not installed in this environment")
    }
}

@discardableResult
private func gitRun(_ args: [String], at directoryURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directoryURL
    process.environment = GitCLI.enrichedEnvironment()

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData + errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0 else {
        XCTFail(output)
        throw TemporaryGitRepository.CommandError(arguments: args, output: output)
    }

    return output
}

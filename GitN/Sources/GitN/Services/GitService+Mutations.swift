import Foundation

// All mutation entry points own the common-repository gate through suspension.
// Implementations compose Unqueued helpers only while this ownership is held.
extension GitService {
    private func withRepositoryMutation<T>(_ body: () async throws -> T) async throws -> T {
        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repoPath)
        let token = try await gate.acquire()
        do {
            try Task.checkCancellation()
            refreshRepositoryState()
            let result = try await body()
            refreshRepositoryState()
            await gate.release(token)
            return result
        } catch {
            refreshRepositoryState()
            await gate.release(token)
            throw error
        }
    }

    func saveWorkingTreeFile(path: String, content: String) async throws {
        try await withRepositoryMutation {
            try self.saveWorkingTreeFileUnqueued(path: path, content: content)
        }
    }

    func stageFile(_ path: String) async throws {
        try await withRepositoryMutation {
            try self.stageFileUnqueued(path)
        }
    }

    func stageFiles(_ paths: [String]) async throws {
        try await withRepositoryMutation {
            try self.stageFilesUnqueued(paths)
        }
    }

    func unstageFile(_ path: String) async throws {
        try await withRepositoryMutation {
            try self.unstageFileUnqueued(path)
        }
    }

    func unstageFiles(_ paths: [String]) async throws {
        try await withRepositoryMutation {
            try self.unstageFilesUnqueued(paths)
        }
    }

    func fetch(remoteName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.fetchUnqueued(remoteName: remoteName)
        }
    }

    func fetchWithPrune(remoteName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.fetchWithPruneUnqueued(remoteName: remoteName)
        }
    }

    func fetchBranchFastForward(remoteName: String, branchName: String) async throws {
        try await withRepositoryMutation {
            try await self.fetchBranchFastForwardUnqueued(remoteName: remoteName, branchName: branchName)
        }
    }

    func pull(remoteName: String? = nil, branchName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.pullUnqueued(remoteName: remoteName, branchName: branchName)
        }
    }

    func pullFF(remoteName: String? = nil, branchName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.pullFFUnqueued(remoteName: remoteName, branchName: branchName)
        }
    }

    func pullRebase(remoteName: String? = nil, branchName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.pullRebaseUnqueued(remoteName: remoteName, branchName: branchName)
        }
    }

    func pullForce() async throws {
        try await withRepositoryMutation {
            try await self.pullForceUnqueued()
        }
    }

    func push(remoteName: String? = nil, branchName: String? = nil, setUpstream: Bool = false) async throws {
        try await withRepositoryMutation {
            try await self.pushUnqueued(remoteName: remoteName, branchName: branchName, setUpstream: setUpstream)
        }
    }

    func pushForce(remoteName: String? = nil, branchName: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.pushForceUnqueued(remoteName: remoteName, branchName: branchName)
        }
    }

    func fetchStreaming(
        remoteName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.fetchStreamingUnqueued(remoteName: remoteName, onOutput: onOutput)
        }
    }

    func fetchWithPruneStreaming(
        remoteName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.fetchWithPruneStreamingUnqueued(remoteName: remoteName, onOutput: onOutput)
        }
    }

    func pullStreaming(
        remoteName: String? = nil,
        branchName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pullStreamingUnqueued(remoteName: remoteName, branchName: branchName, onOutput: onOutput)
        }
    }

    func pullFFStreaming(
        remoteName: String? = nil,
        branchName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pullFFStreamingUnqueued(remoteName: remoteName, branchName: branchName, onOutput: onOutput)
        }
    }

    func pullRebaseStreaming(
        remoteName: String? = nil,
        branchName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pullRebaseStreamingUnqueued(remoteName: remoteName, branchName: branchName, onOutput: onOutput)
        }
    }

    func pullForceStreaming(
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pullForceStreamingUnqueued(onOutput: onOutput)
        }
    }

    func pushStreaming(
        remoteName: String? = nil,
        branchName: String? = nil,
        setUpstream: Bool = false,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pushStreamingUnqueued(remoteName: remoteName, branchName: branchName, setUpstream: setUpstream, onOutput: onOutput)
        }
    }

    func pushForceStreaming(
        remoteName: String? = nil,
        branchName: String? = nil,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pushForceStreamingUnqueued(remoteName: remoteName, branchName: branchName, onOutput: onOutput)
        }
    }

    func pushTagStreaming(
        name: String,
        remote: String,
        onOutput: @escaping @Sendable (Data?, Data?) -> Void
    ) async throws {
        try await withRepositoryMutation {
            try await self.pushTagStreamingUnqueued(name: name, remote: remote, onOutput: onOutput)
        }
    }

    func createBranch(name: String, checkout: Bool = true) async throws {
        try await withRepositoryMutation {
            try self.createBranchUnqueued(name: name, checkout: checkout)
        }
    }

    func createBranchAt(name: String, commitHash: String) async throws {
        try await withRepositoryMutation {
            try self.createBranchAtUnqueued(name: name, commitHash: commitHash)
        }
    }

    func checkoutBranch(_ name: String) async throws {
        try await withRepositoryMutation {
            try self.checkoutBranchUnqueued(name)
        }
    }

    func checkoutCommit(_ hash: String) async throws {
        try await withRepositoryMutation {
            try self.checkoutCommitUnqueued(hash)
        }
    }

    func merge(_ branchOrHash: String) async throws {
        try await withRepositoryMutation {
            try await self.mergeUnqueued(branchOrHash)
        }
    }

    func rebase(onto target: String) async throws {
        try await withRepositoryMutation {
            try await self.rebaseUnqueued(onto: target)
        }
    }

    func mergeCapturingOutput(_ branchOrHash: String) async throws -> OperationOutput {
        try await withRepositoryMutation {
            try await self.mergeCapturingOutputUnqueued(branchOrHash)
        }
    }

    func rebaseCapturingOutput(onto target: String) async throws -> OperationOutput {
        try await withRepositoryMutation {
            try await self.rebaseCapturingOutputUnqueued(onto: target)
        }
    }

    func cherryPick(_ hash: String) async throws {
        try await withRepositoryMutation {
            try await self.cherryPickUnqueued(hash)
        }
    }

    func resetToCommit(_ hash: String, mode: ResetMode) async throws {
        try await withRepositoryMutation {
            try self.resetToCommitUnqueued(hash, mode: mode)
        }
    }

    func revertCommit(_ hash: String) async throws {
        try await withRepositoryMutation {
            try await self.revertCommitUnqueued(hash)
        }
    }

    func deleteBranch(_ name: String, force: Bool = false) async throws {
        try await withRepositoryMutation {
            try self.deleteBranchUnqueued(name, force: force)
        }
    }

    func renameBranch(oldName: String, newName: String) async throws {
        try await withRepositoryMutation {
            try self.renameBranchUnqueued(oldName: oldName, newName: newName)
        }
    }

    func deleteRemoteBranch(remote: String, branch: String) async throws -> DeleteRemoteBranchResult {
        try await withRepositoryMutation {
            try await self.deleteRemoteBranchUnqueued(remote: remote, branch: branch)
        }
    }

    func createTag(name: String, at hash: String, message: String? = nil) async throws {
        try await withRepositoryMutation {
            try self.createTagUnqueued(name: name, at: hash, message: message)
        }
    }

    func deleteTag(name: String) async throws {
        try await withRepositoryMutation {
            try self.deleteTagUnqueued(name: name)
        }
    }

    func pushTag(name: String, remote: String) async throws {
        try await withRepositoryMutation {
            try await self.pushTagUnqueued(name: name, remote: remote)
        }
    }

    func deleteRemoteTag(name: String, remote: String) async throws {
        try await withRepositoryMutation {
            try await self.deleteRemoteTagUnqueued(name: name, remote: remote)
        }
    }

    func annotateTag(name: String, message: String) async throws {
        try await withRepositoryMutation {
            try await self.annotateTagUnqueued(name: name, message: message)
        }
    }

    func setUpstream(remote: String, branch: String) async throws {
        try await withRepositoryMutation {
            try self.setUpstreamUnqueued(remote: remote, branch: branch)
        }
    }

    func unsetUpstream(branch: String) async throws {
        try await withRepositoryMutation {
            try self.unsetUpstreamUnqueued(branch: branch)
        }
    }

    func editCommitMessage(_ hash: String, newMessage: String) async throws {
        try await withRepositoryMutation {
            try await self.editCommitMessageUnqueued(hash, newMessage: newMessage)
        }
    }

    func amendCommitMessage(_ newMessage: String) async throws {
        try await withRepositoryMutation {
            try await self.amendCommitMessageUnqueued(newMessage)
        }
    }

    func rewordCommitMessage(hash: String, newMessage: String) async throws {
        try await withRepositoryMutation {
            try await self.rewordCommitMessageUnqueued(hash: hash, newMessage: newMessage)
        }
    }

    func squashCommits(_ hashes: [String]) async throws {
        try await withRepositoryMutation {
            try await self.squashCommitsUnqueued(hashes)
        }
    }

    func addRemote(name: String, url: String) async throws {
        try await withRepositoryMutation {
            try self.addRemoteUnqueued(name: name, url: url)
        }
    }

    func deleteRemote(name: String) async throws {
        try await withRepositoryMutation {
            try self.deleteRemoteUnqueued(name: name)
        }
    }

    func renameRemote(oldName: String, newName: String) async throws {
        try await withRepositoryMutation {
            try self.renameRemoteUnqueued(oldName: oldName, newName: newName)
        }
    }

    func setRemoteURL(name: String, url: String) async throws {
        try await withRepositoryMutation {
            try self.setRemoteURLUnqueued(name: name, url: url)
        }
    }

    @discardableResult
    func stashSave(message: String?, includeUntracked: Bool = true) async throws -> String {
        try await withRepositoryMutation {
            try self.stashSaveUnqueued(message: message, includeUntracked: includeUntracked)
        }
    }

    func stashPop(oid: String) async throws {
        try await withRepositoryMutation {
            try await self.stashPopUnqueued(oid: oid)
        }
    }

    func stashApply(oid: String) async throws {
        try await withRepositoryMutation {
            try await self.stashApplyUnqueued(oid: oid)
        }
    }

    func stashDrop(oid: String) async throws {
        try await withRepositoryMutation {
            try self.stashDropUnqueued(oid: oid)
        }
    }

    func stashPop(index: Int = 0) async throws {
        try await withRepositoryMutation {
            try await self.stashPopUnqueued(index: index)
        }
    }

    func stashApply(index: Int = 0) async throws {
        try await withRepositoryMutation {
            try await self.stashApplyUnqueued(index: index)
        }
    }

    func stashDrop(index: Int = 0) async throws {
        try await withRepositoryMutation {
            try self.stashDropUnqueued(index: index)
        }
    }

    func applyPatch(_ patch: String, cached: Bool = false, reverse: Bool = false) async throws {
        try await withRepositoryMutation {
            try await self.applyPatchUnqueued(patch, cached: cached, reverse: reverse)
        }
    }

    func discardFileChanges(path: String) async throws {
        try await withRepositoryMutation {
            try self.discardFileChangesUnqueued(path: path)
        }
    }

    func addToGitignore(pattern: String) async throws {
        try await withRepositoryMutation {
            try await self.addToGitignoreUnqueued(pattern: pattern)
        }
    }

    func mergeAbort() async throws {
        try await withRepositoryMutation {
            try await self.mergeAbortUnqueued()
        }
    }

    func stashConflictAbort() async throws {
        try await withRepositoryMutation {
            try await self.stashConflictAbortUnqueued()
        }
    }

    func markConflictResolved(path: String) async throws {
        try await withRepositoryMutation {
            try await self.markConflictResolvedUnqueued(path: path)
        }
    }

    func markAllConflictsResolved() async throws {
        try await withRepositoryMutation {
            try await self.markAllConflictsResolvedUnqueued()
        }
    }

    func markFileConflicted(path: String) async throws {
        try await withRepositoryMutation {
            try self.markFileConflictedUnqueued(path: path)
        }
    }

    func rebaseContinue(message: String? = nil) async throws {
        try await withRepositoryMutation {
            try await self.rebaseContinueUnqueued(message: message)
        }
    }

    func rebaseSkip() async throws {
        try await withRepositoryMutation {
            try await self.rebaseSkipUnqueued()
        }
    }

    func rebaseAbort() async throws {
        try await withRepositoryMutation {
            try await self.rebaseAbortUnqueued()
        }
    }

    func saveConflictResolution(
        path: String, content: String, expectedSnapshot: ConflictFileSnapshot
    ) async throws {
        try await withRepositoryMutation {
            try self.saveConflictResolutionUnqueued(path: path, content: content, expectedSnapshot: expectedSnapshot)
        }
    }

    func resolveDeleteModifyConflict(
        path: String, choice: DeleteModifyResolution, expectedSnapshot: ConflictFileSnapshot
    ) async throws {
        try await withRepositoryMutation {
            try await self.resolveDeleteModifyConflictUnqueued(
                path: path, choice: choice, expectedSnapshot: expectedSnapshot
            )
        }
    }

    func commitAmend(message: String) async throws {
        try await withRepositoryMutation {
            try await self.commitAmendUnqueued(message: message)
        }
    }

    func commitAmendCapturingOutput(message: String) async throws -> OperationOutput {
        try await withRepositoryMutation {
            try await self.commitAmendCapturingOutputUnqueued(message: message)
        }
    }

    func commit(message: String) async throws {
        try await withRepositoryMutation {
            try self.commitUnqueued(message: message)
        }
    }
}

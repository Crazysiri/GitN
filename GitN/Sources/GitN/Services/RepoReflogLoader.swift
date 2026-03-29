import Foundation

struct RepoReflogSnapshot: Sendable {
    let entries: [ReflogEntryInfo]
    let entriesByCommitHash: [String: [ReflogEntryInfo]]
    let recoveredCommits: [CommitInfo]
    let recoveryEntriesByCommitHash: [String: [ReflogEntryInfo]]

    static let empty = RepoReflogSnapshot(
        entries: [],
        entriesByCommitHash: [:],
        recoveredCommits: [],
        recoveryEntriesByCommitHash: [:]
    )
}

struct RepoReflogLoader: Sendable {
    let git: GitService
    let maxCount: Int

    init(git: GitService, maxCount: Int = 250) {
        self.git = git
        self.maxCount = maxCount
    }

    func load(refName: String) async throws -> RepoReflogSnapshot {
        let entries = try await git.reflog(refName: refName, maxCount: maxCount)
        let entriesByCommitHash = Self.groupVisibleEntries(entries)
        let candidateHashes = Self.candidateHashes(from: entries)
        let reachable = try await git.reachableCommitHashes(matching: candidateHashes)
        let lostHashes = Self.orderedLostHashes(from: entries, reachable: reachable)
        let recoveryEntriesByCommitHash = Self.groupRecoveryEntries(entries, lostHashes: Set(lostHashes))

        var recoveredCommits: [CommitInfo] = []
        recoveredCommits.reserveCapacity(lostHashes.count)
        for hash in lostHashes {
            if let commit = try? await git.commitInfo(hash: hash) {
                recoveredCommits.append(commit)
            }
        }

        return RepoReflogSnapshot(
            entries: entries,
            entriesByCommitHash: entriesByCommitHash,
            recoveredCommits: recoveredCommits,
            recoveryEntriesByCommitHash: recoveryEntriesByCommitHash
        )
    }

    private static func groupVisibleEntries(_ entries: [ReflogEntryInfo]) -> [String: [ReflogEntryInfo]] {
        Dictionary(grouping: entries.compactMap { entry -> (String, ReflogEntryInfo)? in
            guard let hash = entry.newOID else { return nil }
            return (hash, entry)
        }, by: \.0).mapValues { $0.map(\.1) }
    }

    private static func candidateHashes(from entries: [ReflogEntryInfo]) -> [String] {
        Array(Set(entries.flatMap { entry in
            [entry.oldOID, entry.newOID].compactMap { $0 }
        }))
    }

    private static func orderedLostHashes(from entries: [ReflogEntryInfo], reachable: Set<String>) -> [String] {
        entries.flatMap { entry in
            [entry.oldOID, entry.newOID].compactMap { hash -> String? in
                guard let hash, !reachable.contains(hash) else { return nil }
                return hash
            }
        }.reduce(into: [String]()) { result, hash in
            if !result.contains(hash) {
                result.append(hash)
            }
        }
    }

    private static func groupRecoveryEntries(
        _ entries: [ReflogEntryInfo],
        lostHashes: Set<String>
    ) -> [String: [ReflogEntryInfo]] {
        Dictionary(grouping: entries.compactMap { entry -> (String, ReflogEntryInfo)? in
            if let oldOID = entry.oldOID, lostHashes.contains(oldOID) {
                return (oldOID, entry)
            }
            if let newOID = entry.newOID, lostHashes.contains(newOID) {
                return (newOID, entry)
            }
            return nil
        }, by: \.0).mapValues { $0.map(\.1) }
    }
}

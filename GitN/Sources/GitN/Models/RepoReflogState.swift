import Foundation

struct RepoReflogState {
    let currentBranch: String
    let isDetachedHead: Bool
    let baseCommits: [CommitInfo]
    let recoveredCommits: [CommitInfo]
    let visibleEntriesByCommitHash: [String: [ReflogEntryInfo]]
    let recoveryEntriesByCommitHash: [String: [ReflogEntryInfo]]
    let showReflogOverlay: Bool
    let allCommitsLoaded: Bool

    var sourceOptions: [ReflogSourceOption] {
        var options = [ReflogSourceOption(refName: "HEAD", title: "HEAD")]
        if !isDetachedHead, !currentBranch.isEmpty {
            options.append(ReflogSourceOption(refName: "refs/heads/\(currentBranch)", title: currentBranch))
        }
        return options
    }

    var mergedEntriesByCommitHash: [String: [ReflogEntryInfo]] {
        let hashes = Set(visibleEntriesByCommitHash.keys).union(recoveryEntriesByCommitHash.keys)
        return Dictionary(uniqueKeysWithValues: hashes.map { ($0, mergedEntries(for: $0)) })
    }

    var badgeEntriesByCommitHash: [String: [ReflogEntryInfo]] {
        Dictionary(uniqueKeysWithValues: mergedEntriesByCommitHash.keys.map { ($0, badgeEntries(for: $0)) })
    }

    func mergedEntries(for commitHash: String) -> [ReflogEntryInfo] {
        let visible = visibleEntriesByCommitHash[commitHash] ?? []
        let recovered = recoveryEntriesByCommitHash[commitHash] ?? []
        var merged: [String: ReflogEntryInfo] = [:]
        for entry in visible + recovered {
            merged[entry.id] = entry
        }
        return merged.values.sorted { $0.index < $1.index }
    }

    func badgeEntries(for commitHash: String) -> [ReflogEntryInfo] {
        var seenKinds: Set<String> = []
        return mergedEntries(for: commitHash).filter { entry in
            seenKinds.insert(entry.kind.rawValue).inserted
        }
    }

    var displayCommits: [CommitInfo] {
        guard showReflogOverlay, !recoveredCommits.isEmpty else { return baseCommits }

        let pinnedPrefix: [CommitInfo]
        let commitRows: [CommitInfo]
        if let first = baseCommits.first, first.isUncommitted {
            pinnedPrefix = [first]
            commitRows = Array(baseCommits.dropFirst())
        } else {
            pinnedPrefix = []
            commitRows = baseCommits
        }

        let recoveredByHash = Dictionary(uniqueKeysWithValues: recoveredCommits.map { ($0.hash, $0) })
        let recoveredHashes = Set(recoveredByHash.keys)
        let childHashes = Set(recoveredCommits.compactMap(\.parentHashes.first).filter { recoveredHashes.contains($0) })

        func reflogRank(for commit: CommitInfo) -> Int {
            recoveryEntriesByCommitHash[commit.hash]?.map(\.index).min() ?? .max
        }

        var visited: Set<String> = []
        var chainsByAnchor: [String: [[CommitInfo]]] = [:]

        func storeChain(startingAt tip: CommitInfo) {
            guard !visited.contains(tip.hash) else { return }

            var chain: [CommitInfo] = []
            var current: CommitInfo? = tip
            var anchorHash: String?

            while let commit = current, !visited.contains(commit.hash) {
                chain.append(commit)
                visited.insert(commit.hash)
                let parentHash = commit.parentHashes.first
                if let parentHash, let recoveredParent = recoveredByHash[parentHash] {
                    current = recoveredParent
                } else {
                    anchorHash = parentHash
                    current = nil
                }
            }

            guard !chain.isEmpty else { return }
            chainsByAnchor[anchorHash ?? "__root__", default: []].append(chain)
        }

        for commit in recoveredCommits where !childHashes.contains(commit.hash) {
            storeChain(startingAt: commit)
        }
        for commit in recoveredCommits where !visited.contains(commit.hash) {
            storeChain(startingAt: commit)
        }

        for key in chainsByAnchor.keys {
            chainsByAnchor[key]?.sort { lhs, rhs in
                guard let leftTip = lhs.first, let rightTip = rhs.first else {
                    return lhs.count > rhs.count
                }
                return reflogRank(for: leftTip) < reflogRank(for: rightTip)
            }
        }

        var result: [CommitInfo] = []
        if let rootChains = chainsByAnchor["__root__"] {
            result.append(contentsOf: rootChains.flatMap { $0 })
        }
        for commit in commitRows {
            if let anchoredChains = chainsByAnchor[commit.hash] {
                result.append(contentsOf: anchoredChains.flatMap { $0 })
            }
            result.append(commit)
        }
        return pinnedPrefix + result
    }

    func canNavigateToCommit(hash: String?) -> Bool {
        guard let hash, !hash.isEmpty else { return false }
        if baseCommits.contains(where: { Self.matches($0, hash: hash) }) ||
            recoveredCommits.contains(where: { Self.matches($0, hash: hash) }) {
            return true
        }
        return !allCommitsLoaded
    }

    func displayCommit(matching hash: String) -> CommitInfo? {
        displayCommits.first(where: { Self.matches($0, hash: hash) })
    }

    func isRecoveredCommit(_ commit: CommitInfo) -> Bool {
        recoveredCommits.contains(where: { $0.hash == commit.hash })
    }

    static func matches(_ commit: CommitInfo, hash: String) -> Bool {
        commit.hash == hash || commit.hash.hasPrefix(hash) || hash.hasPrefix(commit.hash)
    }
}

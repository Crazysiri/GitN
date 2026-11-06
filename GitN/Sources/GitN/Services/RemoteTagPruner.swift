import CryptoKit
import Foundation

/// Tracks only tags GitN demonstrably acquired from a remote during Sync.
/// Git has no separate remote-tag namespace, so names alone cannot prove ownership.
@MainActor
final class RemoteTagPruner {
    private let repoPath: String
    private let cli: GitCLI
    private let defaults: UserDefaults
    private let storageKey: String

    init(repoPath: String, defaults: UserDefaults = .standard) {
        self.repoPath = repoPath
        self.cli = GitCLI(repoPath: repoPath)
        self.defaults = defaults
        self.storageKey = "GitN.remoteTagOwnership.v1." + (repoPath as NSString).standardizingPath
    }

    func localTagOIDs() async throws -> [String: String] {
        let output = try await cli.output(["for-each-ref", "--format=%(refname:strip=2)%09%(objectname)", "refs/tags"])
        return try Self.parseTagRefs(output, prefix: nil)
    }

    /// Called only after the fetch succeeds. Any failed remote query leaves refs and provenance untouched.
    func pruneAfterSuccessfulFetch(
        remotes: [RemoteInfo],
        localTagsBeforeFetch: [String: String]
    ) async throws -> Int {
        guard !remotes.isEmpty else { return 0 }

        var observed: [String: [String: String]] = [:]
        for remote in remotes {
            let output = try await cli.output(["ls-remote", "--tags", "--refs", remote.name])
            observed[Self.identity(for: remote)] = try Self.parseTagRefs(output, prefix: "refs/tags/")
        }

        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repoPath)
        let token = try await gate.acquire()
        do {
            try Task.checkCancellation()
            let deleted = try await pruneObservedTags(
                observed, localTagsBeforeFetch: localTagsBeforeFetch
            )
            await gate.release(token)
            return deleted
        } catch {
            await gate.release(token)
            throw error
        }
    }

    private func pruneObservedTags(
        _ observed: [String: [String: String]], localTagsBeforeFetch: [String: String]
    ) async throws -> Int {
        let localTagsAfterFetch = try await localTagOIDs()
        let previous = loadOwnership()
        let remoteTagNames = Set(observed.values.flatMap { $0.keys })
        var refsToDelete: [String: String] = [:]

        for (identity, tags) in previous where observed[identity] != nil {
            for (name, oid) in tags where !remoteTagNames.contains(name) {
                if localTagsAfterFetch[name] == oid {
                    refsToDelete[name] = oid
                }
            }
        }

        if !refsToDelete.isEmpty {
            // A single ref transaction avoids partial cleanup and expected OIDs protect edits
            // made by another Git process after the local snapshot was read.
            var commands = "start\n"
            for name in refsToDelete.keys.sorted() {
                guard let oid = refsToDelete[name] else { continue }
                commands += "delete refs/tags/\(name) \(oid)\n"
            }
            commands += "prepare\ncommit\n"
            try await cli.run(["update-ref", "--stdin"], input: commands)
        }

        var next: [String: [String: String]] = [:]
        for (identity, tags) in observed {
            var owned: [String: String] = [:]
            for (name, oid) in tags where localTagsAfterFetch[name] == oid {
                if previous[identity]?[name] == oid || localTagsBeforeFetch[name] == nil {
                    owned[name] = oid
                }
            }
            next[identity] = owned
        }
        saveOwnership(next)
        return refsToDelete.count
    }

    private static func identity(for remote: RemoteInfo) -> String {
        let value = Data((remote.name + "\n" + remote.url).utf8)
        return SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseTagRefs(_ output: String, prefix: String?) throws -> [String: String] {
        var tags: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                throw GitError.operationFailed("Malformed tag reference listing")
            }
            let name: String
            let oid: String
            if let prefix {
                guard fields[1].hasPrefix(prefix) else {
                    throw GitError.operationFailed("Unexpected remote tag reference")
                }
                name = String(fields[1].dropFirst(prefix.count))
                oid = String(fields[0])
            } else {
                name = String(fields[0])
                oid = String(fields[1])
            }
            guard !name.isEmpty, (oid.count == 40 || oid.count == 64),
                  oid.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
                throw GitError.operationFailed("Malformed tag reference listing")
            }
            tags[name] = oid
        }
        return tags
    }

    private func loadOwnership() -> [String: [String: String]] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }

    private func saveOwnership(_ ownership: [String: [String: String]]) {
        guard let data = try? JSONEncoder().encode(ownership) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

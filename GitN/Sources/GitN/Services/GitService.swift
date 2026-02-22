import Foundation
import Clibgit2

// MARK: - Callback context types (for C function pointer callbacks)

private final class StashCallbackData {
    var items: [(index: String, message: String)] = []
}

private final class SubmoduleCallbackData {
    var items: [(name: String, hash: String)] = []
}

// MARK: - Error

enum GitError: LocalizedError {
    case repoNotOpen
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .repoNotOpen: return "Repository not open"
        case .operationFailed(let msg): return msg
        }
    }
}

// MARK: - Signature (Xit-style with fallback)

private func makeDefaultSignature(repo: OpaquePointer) -> UnsafeMutablePointer<git_signature>? {
    var sig: UnsafeMutablePointer<git_signature>?
    if git_signature_default(&sig, repo) == 0 {
        return sig
    }

    var config: OpaquePointer?
    guard git_repository_config(&config, repo) == 0, let config else {
        return createFallbackSignature()
    }
    defer { git_config_free(config) }

    var nameBuf = git_buf()
    var emailBuf = git_buf()
    let nameOk = git_config_get_string_buf(&nameBuf, config, "user.name") == 0
    let emailOk = git_config_get_string_buf(&emailBuf, config, "user.email") == 0

    let name = nameOk ? String(cString: nameBuf.ptr) : NSFullUserName().isEmpty ? "GitN User" : NSFullUserName()
    let email = emailOk ? String(cString: emailBuf.ptr) : "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"

    if nameOk { git_buf_dispose(&nameBuf) }
    if emailOk { git_buf_dispose(&emailBuf) }

    if git_signature_now(&sig, name, email) == 0 {
        return sig
    }
    return nil
}

private func createFallbackSignature() -> UnsafeMutablePointer<git_signature>? {
    let name = NSFullUserName().isEmpty ? "GitN User" : NSFullUserName()
    let email = "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
    var sig: UnsafeMutablePointer<git_signature>?
    if git_signature_now(&sig, name, email) == 0 {
        return sig
    }
    return nil
}

// MARK: - Service

actor GitService {
    let repoPath: String
    private var repo: OpaquePointer?

    init(repoPath: String) {
        self.repoPath = repoPath
        git_libgit2_init()
        var r: OpaquePointer?
        if git_repository_open(&r, repoPath) == 0 {
            self.repo = r
        }
    }

    deinit {
        if let repo { git_repository_free(repo) }
        git_libgit2_shutdown()
    }

    // MARK: - OID Helpers

    private nonisolated func oidToHash(_ ptr: UnsafePointer<git_oid>) -> String {
        var buf = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&buf, 41, ptr)
        return String(cString: buf)
    }

    private nonisolated func oidToShortHash(_ ptr: UnsafePointer<git_oid>) -> String {
        var buf = [CChar](repeating: 0, count: 8)
        git_oid_tostr(&buf, 8, ptr)
        return String(cString: buf)
    }

    private nonisolated func formatGitTime(_ time: git_time) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time.time))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let totalMinutes = Int(time.offset)
        fmt.timeZone = TimeZone(secondsFromGMT: totalMinutes * 60)
        let sign = totalMinutes >= 0 ? "+" : "-"
        let abs = Swift.abs(totalMinutes)
        return fmt.string(from: date) + " " + String(format: "%@%02d%02d", sign, abs / 60, abs % 60)
    }

    // MARK: - HEAD

    func headCommitHash() throws -> String? {
        guard let repo else { throw GitError.repoNotOpen }
        var head: OpaquePointer?
        guard git_repository_head(&head, repo) == 0, let head else { return nil }
        defer { git_reference_free(head) }
        guard let oid = git_reference_target(head) else { return nil }
        return oidToHash(oid)
    }

    // MARK: - Branches

    func localBranches() throws -> [BranchInfo] {
        guard let repo else { throw GitError.repoNotOpen }
        var result: [BranchInfo] = []

        var iter: OpaquePointer?
        guard git_branch_iterator_new(&iter, repo, GIT_BRANCH_LOCAL) == 0,
              let iter else { return [] }
        defer { git_branch_iterator_free(iter) }

        var ref: OpaquePointer?
        var branchType = GIT_BRANCH_LOCAL
        while git_branch_next(&ref, &branchType, iter) == 0, let ref {
            defer { git_reference_free(ref) }

            var nameC: UnsafePointer<CChar>?
            git_branch_name(&nameC, ref)
            let name = nameC.map(String.init(cString:)) ?? ""

            let oid = git_reference_target(ref)
            let shortHash = oid.map { oidToShortHash($0) } ?? ""
            let isHead = git_branch_is_head(ref) == 1

            var upstream: OpaquePointer?
            var upstreamName: String?
            var ahead: Int = 0
            var behind: Int = 0
            if git_branch_upstream(&upstream, ref) == 0, let upstream {
                var uname: UnsafePointer<CChar>?
                git_branch_name(&uname, upstream)
                upstreamName = uname.map(String.init(cString:))

                if let localOid = git_reference_target(ref),
                   let upstreamOid = git_reference_target(upstream) {
                    var a: Int = 0, b: Int = 0
                    var localCopy = localOid.pointee
                    var upstreamCopy = upstreamOid.pointee
                    if git_graph_ahead_behind(&a, &b, repo, &localCopy, &upstreamCopy) == 0 {
                        ahead = a
                        behind = b
                    }
                }
                git_reference_free(upstream)
            }

            result.append(BranchInfo(
                name: name, shortHash: shortHash,
                upstream: upstreamName, isCurrent: isHead, isRemote: false,
                ahead: ahead, behind: behind
            ))
        }
        return result
    }

    func remoteBranches() throws -> [BranchInfo] {
        guard let repo else { throw GitError.repoNotOpen }
        var result: [BranchInfo] = []

        var iter: OpaquePointer?
        guard git_branch_iterator_new(&iter, repo, GIT_BRANCH_REMOTE) == 0,
              let iter else { return [] }
        defer { git_branch_iterator_free(iter) }

        var ref: OpaquePointer?
        var branchType = GIT_BRANCH_REMOTE
        while git_branch_next(&ref, &branchType, iter) == 0, let ref {
            defer { git_reference_free(ref) }

            var nameC: UnsafePointer<CChar>?
            git_branch_name(&nameC, ref)
            let name = nameC.map(String.init(cString:)) ?? ""

            let oid = git_reference_target(ref)
            let shortHash = oid.map { oidToShortHash($0) } ?? ""

            result.append(BranchInfo(
                name: name, shortHash: shortHash,
                upstream: nil, isCurrent: false, isRemote: true
            ))
        }
        return result
    }

    func currentBranch() throws -> String {
        guard let repo else { throw GitError.repoNotOpen }
        var head: OpaquePointer?
        guard git_repository_head(&head, repo) == 0, let head else { return "" }
        defer { git_reference_free(head) }

        if git_reference_is_branch(head) == 1 {
            var nameC: UnsafePointer<CChar>?
            git_branch_name(&nameC, head)
            return nameC.map(String.init(cString:)) ?? ""
        }
        if let oid = git_reference_target(head) {
            return oidToShortHash(oid)
        }
        return "HEAD"
    }

    // MARK: - Tags

    func tags() throws -> [String] {
        guard let repo else { throw GitError.repoNotOpen }
        var tagNames = git_strarray()
        guard git_tag_list(&tagNames, repo) == 0 else { return [] }
        defer { git_strarray_dispose(&tagNames) }

        var result: [String] = []
        for i in 0..<tagNames.count {
            if let s = tagNames.strings[i] {
                result.append(String(cString: s))
            }
        }
        return result.reversed()
    }

    // MARK: - Remotes

    func remotes() throws -> [RemoteInfo] {
        guard let repo else { throw GitError.repoNotOpen }
        var remoteNames = git_strarray()
        guard git_remote_list(&remoteNames, repo) == 0 else { return [] }
        defer { git_strarray_dispose(&remoteNames) }

        var result: [RemoteInfo] = []
        for i in 0..<remoteNames.count {
            guard let nameC = remoteNames.strings[i] else { continue }
            let name = String(cString: nameC)

            var remote: OpaquePointer?
            guard git_remote_lookup(&remote, repo, nameC) == 0, let remote else { continue }
            defer { git_remote_free(remote) }

            let url = git_remote_url(remote).map(String.init(cString:)) ?? ""
            result.append(RemoteInfo(name: name, url: url))
        }
        return result
    }

    // MARK: - Stashes

    func stashes() throws -> [StashInfo] {
        guard let repo else { throw GitError.repoNotOpen }

        let data = StashCallbackData()
        let ctx = Unmanaged.passRetained(data).toOpaque()
        defer { Unmanaged<StashCallbackData>.fromOpaque(ctx).release() }

        git_stash_foreach(repo, { index, message, _, payload in
            guard let payload else { return 0 }
            let d = Unmanaged<StashCallbackData>.fromOpaque(payload).takeUnretainedValue()
            d.items.append((
                index: "stash@{\(index)}",
                message: message.map(String.init(cString:)) ?? ""
            ))
            return 0
        }, ctx)

        return data.items.map {
            StashInfo(index: $0.index, message: $0.message, date: "")
        }
    }

    // MARK: - Submodules

    func submodules() throws -> [SubmoduleInfo] {
        guard let repo else { throw GitError.repoNotOpen }

        let data = SubmoduleCallbackData()
        let ctx = Unmanaged.passRetained(data).toOpaque()
        defer { Unmanaged<SubmoduleCallbackData>.fromOpaque(ctx).release() }

        git_submodule_foreach(repo, { submodule, name, payload in
            guard let payload, let name else { return 0 }
            let d = Unmanaged<SubmoduleCallbackData>.fromOpaque(payload).takeUnretainedValue()
            let nameStr = String(cString: name)
            var hashStr = ""
            if let submodule, let headId = git_submodule_head_id(submodule) {
                var buf = [CChar](repeating: 0, count: 41)
                git_oid_tostr(&buf, 41, headId)
                hashStr = String(cString: buf)
            }
            d.items.append((name: nameStr, hash: hashStr))
            return 0
        }, ctx)

        return data.items.map {
            SubmoduleInfo(name: $0.name, hash: $0.hash)
        }
    }

    // MARK: - Commit Log

    func commitLog(maxCount: Int = 200) throws -> [CommitInfo] {
        guard let repo else { throw GitError.repoNotOpen }

        let refMap = buildRefMap()

        var walker: OpaquePointer?
        guard git_revwalk_new(&walker, repo) == 0, let walker else { return [] }
        defer { git_revwalk_free(walker) }

        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        git_revwalk_push_glob(walker, "refs/heads/*")
        git_revwalk_push_glob(walker, "refs/remotes/*")

        var result: [CommitInfo] = []
        var oid = git_oid()
        var count = 0

        while count < maxCount, git_revwalk_next(&oid, walker) == 0 {
            var commit: OpaquePointer?
            guard git_commit_lookup(&commit, repo, &oid) == 0, let commit else { continue }
            defer { git_commit_free(commit) }

            let hash = oidToHash(&oid)
            let shortHash = oidToShortHash(&oid)

            let parentCount = git_commit_parentcount(commit)
            var parentHashes: [String] = []
            for i in 0..<parentCount {
                if let pid = git_commit_parent_id(commit, i) {
                    parentHashes.append(oidToHash(pid))
                }
            }

            let authorName: String
            let authorEmail: String
            let date: String
            if let sig = git_commit_author(commit) {
                authorName = String(cString: sig.pointee.name)
                authorEmail = String(cString: sig.pointee.email)
                date = formatGitTime(sig.pointee.when)
            } else {
                authorName = ""; authorEmail = ""; date = ""
            }

            let message = git_commit_message(commit).map(String.init(cString:))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstLine = message.components(separatedBy: .newlines).first ?? message

            let refs = refMap[hash] ?? []

            result.append(CommitInfo(
                hash: hash, shortHash: shortHash,
                parentHashes: parentHashes,
                authorName: authorName, authorEmail: authorEmail,
                date: date, message: firstLine, refs: refs
            ))
            count += 1
        }
        return result
    }

    /// Streaming commit log that yields batches progressively (like gitx's PBGitRevList).
    /// Opens a separate repo handle on a detached task for true parallelism.
    /// The first batch is smaller for fast initial display; subsequent batches are larger.
    func commitLogStream(firstBatch: Int = 500, batchSize: Int = 5000) -> AsyncStream<[CommitInfo]> {
        let refMap = buildRefMap()
        let path = repoPath
        let (stream, continuation) = AsyncStream.makeStream(of: [CommitInfo].self)

        Task.detached(priority: .userInitiated) {
            Self._produceCommitBatches(
                repoPath: path, refMap: refMap,
                firstBatch: firstBatch, batchSize: batchSize,
                continuation: continuation
            )
        }

        return stream
    }

    private nonisolated static func _produceCommitBatches(
        repoPath: String,
        refMap: [String: [String]],
        firstBatch: Int,
        batchSize: Int,
        continuation: AsyncStream<[CommitInfo]>.Continuation
    ) {
        var repo: OpaquePointer?
        guard git_repository_open(&repo, repoPath) == 0, let repo else {
            continuation.finish()
            return
        }
        defer { git_repository_free(repo) }

        var walker: OpaquePointer?
        guard git_revwalk_new(&walker, repo) == 0, let walker else {
            continuation.finish()
            return
        }
        defer { git_revwalk_free(walker) }

        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        git_revwalk_push_glob(walker, "refs/heads/*")
        git_revwalk_push_glob(walker, "refs/remotes/*")

        func oidStr(_ ptr: UnsafePointer<git_oid>) -> String {
            var buf = [CChar](repeating: 0, count: 41)
            git_oid_tostr(&buf, 41, ptr)
            return String(cString: buf)
        }
        func shortOidStr(_ ptr: UnsafePointer<git_oid>) -> String {
            var buf = [CChar](repeating: 0, count: 8)
            git_oid_tostr(&buf, 8, ptr)
            return String(cString: buf)
        }
        func fmtTime(_ time: git_time) -> String {
            let date = Date(timeIntervalSince1970: TimeInterval(time.time))
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let totalMinutes = Int(time.offset)
            fmt.timeZone = TimeZone(secondsFromGMT: totalMinutes * 60)
            let sign = totalMinutes >= 0 ? "+" : "-"
            let absMin = Swift.abs(totalMinutes)
            return fmt.string(from: date) + " " + String(format: "%@%02d%02d", sign, absMin / 60, absMin % 60)
        }

        var batch: [CommitInfo] = []
        var isFirstBatch = true
        let currentLimit = firstBatch
        batch.reserveCapacity(currentLimit)
        var oid = git_oid()

        while git_revwalk_next(&oid, walker) == 0 {
            guard !Task.isCancelled else { break }

            var commit: OpaquePointer?
            guard git_commit_lookup(&commit, repo, &oid) == 0, let commit else { continue }
            defer { git_commit_free(commit) }

            let hash = oidStr(&oid)
            let shortHash = shortOidStr(&oid)

            let parentCount = git_commit_parentcount(commit)
            var parentHashes: [String] = []
            for pi in 0..<parentCount {
                if let pid = git_commit_parent_id(commit, pi) {
                    parentHashes.append(oidStr(pid))
                }
            }

            let authorName: String
            let authorEmail: String
            let date: String
            if let sig = git_commit_author(commit) {
                authorName = String(cString: sig.pointee.name)
                authorEmail = String(cString: sig.pointee.email)
                date = fmtTime(sig.pointee.when)
            } else {
                authorName = ""; authorEmail = ""; date = ""
            }

            let message = git_commit_message(commit).map(String.init(cString:))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstLine = message.components(separatedBy: .newlines).first ?? message

            batch.append(CommitInfo(
                hash: hash, shortHash: shortHash,
                parentHashes: parentHashes,
                authorName: authorName, authorEmail: authorEmail,
                date: date, message: firstLine,
                refs: refMap[hash] ?? []
            ))

            let limit = isFirstBatch ? firstBatch : batchSize
            if batch.count >= limit {
                continuation.yield(batch)
                batch = []
                batch.reserveCapacity(batchSize)
                isFirstBatch = false
            }
        }

        if !batch.isEmpty {
            continuation.yield(batch)
        }
        continuation.finish()
    }

    private func buildRefMap() -> [String: [String]] {
        guard let repo else { return [:] }
        var map: [String: [String]] = [:]

        var headTarget: String?
        var headOidHash: String?
        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0, let headRef {
            defer { git_reference_free(headRef) }
            if let oid = git_reference_target(headRef) {
                headOidHash = oidToHash(oid)
            }
            if git_reference_type(headRef) == GIT_REFERENCE_SYMBOLIC,
               let sym = git_reference_symbolic_target(headRef) {
                let full = String(cString: sym)
                if full.hasPrefix("refs/heads/") {
                    headTarget = String(full.dropFirst("refs/heads/".count))
                }
            }
        }

        var iter: OpaquePointer?
        guard git_reference_iterator_new(&iter, repo) == 0, let iter else { return [:] }
        defer { git_reference_iterator_free(iter) }

        var ref: OpaquePointer?
        while git_reference_next(&ref, iter) == 0, let ref {
            defer { git_reference_free(ref) }
            guard let namePtr = git_reference_name(ref) else { continue }
            let fullName = String(cString: namePtr)

            var resolved: OpaquePointer?
            let hash: String?
            if git_reference_resolve(&resolved, ref) == 0, let resolved {
                defer { git_reference_free(resolved) }
                hash = git_reference_target(resolved).map { oidToHash($0) }
            } else {
                hash = git_reference_target(ref).map { oidToHash($0) }
            }
            guard let hash else { continue }

            if fullName.hasPrefix("refs/heads/") {
                let branchName = String(fullName.dropFirst("refs/heads/".count))
                if branchName == headTarget, hash == headOidHash {
                    map[hash, default: []].append("HEAD -> \(branchName)")
                } else {
                    map[hash, default: []].append(branchName)
                }
            } else if fullName.hasPrefix("refs/remotes/") {
                let remoteBranch = String(fullName.dropFirst("refs/remotes/".count))
                if remoteBranch.hasSuffix("/HEAD") { continue }
                map[hash, default: []].append(remoteBranch)
            } else if fullName.hasPrefix("refs/tags/") {
                let tag = String(fullName.dropFirst("refs/tags/".count))
                map[hash, default: []].append("tag: \(tag)")
            }
        }

        for (h, refs) in map {
            map[h] = refs.sorted { a, b in
                func weight(_ s: String) -> Int {
                    if s.hasPrefix("HEAD") { return 0 }
                    if s.hasPrefix("tag:") { return 3 }
                    if s.contains("/") { return 2 }
                    return 1
                }
                return weight(a) < weight(b)
            }
        }
        return map
    }

    // MARK: - Diff Helpers

    private func treeDiff(hash: String) -> OpaquePointer? {
        guard let repo else { return nil }
        var oid = git_oid()
        guard git_oid_fromstr(&oid, hash) == 0 else { return nil }

        var commit: OpaquePointer?
        guard git_commit_lookup(&commit, repo, &oid) == 0, let commit else { return nil }
        defer { git_commit_free(commit) }

        var tree: OpaquePointer?
        guard git_commit_tree(&tree, commit) == 0, let tree else { return nil }
        defer { git_tree_free(tree) }

        var parentTree: OpaquePointer?
        if git_commit_parentcount(commit) > 0 {
            var parent: OpaquePointer?
            if git_commit_parent(&parent, commit, 0) == 0, let parent {
                defer { git_commit_free(parent) }
                git_commit_tree(&parentTree, parent)
            }
        }
        defer { if let parentTree { git_tree_free(parentTree) } }

        var diff: OpaquePointer?
        guard git_diff_tree_to_tree(&diff, repo, parentTree, tree, nil) == 0 else { return nil }
        return diff
    }

    // MARK: - Diff

    func diffForCommit(hash: String) throws -> String {
        guard let diff = treeDiff(hash: hash) else { return "" }
        defer { git_diff_free(diff) }

        var buf = git_buf()
        guard git_diff_to_buf(&buf, diff, GIT_DIFF_FORMAT_PATCH) == 0 else { return "" }
        defer { git_buf_dispose(&buf) }
        return String(cString: buf.ptr)
    }

    func diffStaged() throws -> String {
        guard let repo else { return "" }

        var headTree: OpaquePointer?
        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0, let headRef {
            defer { git_reference_free(headRef) }
            var commitObj: OpaquePointer?
            if git_reference_peel(&commitObj, headRef, GIT_OBJECT_COMMIT) == 0, let commitObj {
                defer { git_object_free(commitObj) }
                git_commit_tree(&headTree, commitObj)
            }
        }
        defer { if let headTree { git_tree_free(headTree) } }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else { return "" }
        defer { git_index_free(index) }

        var diff: OpaquePointer?
        guard git_diff_tree_to_index(&diff, repo, headTree, index, nil) == 0, let diff else { return "" }
        defer { git_diff_free(diff) }

        var buf = git_buf()
        guard git_diff_to_buf(&buf, diff, GIT_DIFF_FORMAT_PATCH) == 0 else { return "" }
        defer { git_buf_dispose(&buf) }
        return String(cString: buf.ptr)
    }

    func diffUnstaged() throws -> String {
        guard let repo else { return "" }

        var diff: OpaquePointer?
        guard git_diff_index_to_workdir(&diff, repo, nil, nil) == 0, let diff else { return "" }
        defer { git_diff_free(diff) }

        var buf = git_buf()
        guard git_diff_to_buf(&buf, diff, GIT_DIFF_FORMAT_PATCH) == 0 else { return "" }
        defer { git_buf_dispose(&buf) }
        return String(cString: buf.ptr)
    }

    func diffDetail(hash: String) throws -> [DiffFile] {
        guard let diff = treeDiff(hash: hash) else { return [] }
        defer { git_diff_free(diff) }

        var result: [DiffFile] = []
        let numDeltas = git_diff_num_deltas(diff)

        for i in 0..<numDeltas {
            var patch: OpaquePointer?
            guard git_patch_from_diff(&patch, diff, i) == 0, let patch else { continue }
            defer { git_patch_free(patch) }

            var adds = 0, dels = 0
            let numHunks = git_patch_num_hunks(patch)
            for h in 0..<numHunks {
                let numLines = git_patch_num_lines_in_hunk(patch, h)
                for l in 0..<Int(numLines) {
                    var line: UnsafePointer<git_diff_line>?
                    if git_patch_get_line_in_hunk(&line, patch, h, l) == 0, let line {
                        if line.pointee.origin == 43 { adds += 1 }      // '+'
                        else if line.pointee.origin == 45 { dels += 1 } // '-'
                    }
                }
            }

            guard let delta = git_patch_get_delta(patch) else { continue }
            let path = delta.pointee.new_file.path.map(String.init(cString:)) ?? ""
            result.append(DiffFile(additions: adds, deletions: dels, path: path))
        }
        return result
    }

    func uncommittedDiffFiles() throws -> [DiffFile] {
        guard let repo else { throw GitError.repoNotOpen }
        var result: [DiffFile] = []

        // HEAD tree for staged diff base
        var headTree: OpaquePointer?
        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0, let headRef {
            defer { git_reference_free(headRef) }
            var commitObj: OpaquePointer?
            if git_reference_peel(&commitObj, headRef, GIT_OBJECT_COMMIT) == 0, let commitObj {
                defer { git_object_free(commitObj) }
                git_commit_tree(&headTree, commitObj)
            }
        }
        defer { if let headTree { git_tree_free(headTree) } }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else { return [] }
        defer { git_index_free(index) }

        // Staged changes (HEAD -> index)
        var stagedDiff: OpaquePointer?
        if git_diff_tree_to_index(&stagedDiff, repo, headTree, index, nil) == 0, let stagedDiff {
            defer { git_diff_free(stagedDiff) }
            result.append(contentsOf: diffFilesFromDiff(stagedDiff))
        }

        // Unstaged changes (index -> workdir)
        var unstagedDiff: OpaquePointer?
        if git_diff_index_to_workdir(&unstagedDiff, repo, nil, nil) == 0, let unstagedDiff {
            defer { git_diff_free(unstagedDiff) }
            for df in diffFilesFromDiff(unstagedDiff) {
                if !result.contains(where: { $0.path == df.path }) {
                    result.append(df)
                }
            }
        }

        return result
    }

    private func diffFilesFromDiff(_ diff: OpaquePointer) -> [DiffFile] {
        var result: [DiffFile] = []
        let numDeltas = git_diff_num_deltas(diff)
        for i in 0..<numDeltas {
            var patch: OpaquePointer?
            guard git_patch_from_diff(&patch, diff, i) == 0, let patch else { continue }
            defer { git_patch_free(patch) }

            var adds = 0, dels = 0
            let numHunks = git_patch_num_hunks(patch)
            for h in 0..<numHunks {
                let numLines = git_patch_num_lines_in_hunk(patch, h)
                for l in 0..<Int(numLines) {
                    var line: UnsafePointer<git_diff_line>?
                    if git_patch_get_line_in_hunk(&line, patch, h, l) == 0, let line {
                        if line.pointee.origin == 43 { adds += 1 }
                        else if line.pointee.origin == 45 { dels += 1 }
                    }
                }
            }
            guard let delta = git_patch_get_delta(patch) else { continue }
            let path = delta.pointee.new_file.path.map(String.init(cString:)) ?? ""
            result.append(DiffFile(additions: adds, deletions: dels, path: path))
        }
        return result
    }

    func uncommittedFileDiff(path: String, statusCode: String) throws -> String {
        guard repo != nil else { throw GitError.repoNotOpen }

        let isUntracked = statusCode == "??"

        if isUntracked {
            return try readFullFileContent(path: path)
        }

        // For staged files, get HEAD→index diff
        let isStaged = {
            let idx = statusCode.first ?? " "
            return idx != " " && idx != "?"
        }()

        if isStaged {
            return try stagedFileDiff(path: path)
        }

        // Unstaged: index→workdir diff
        return try unstagedFileDiff(path: path)
    }

    func readFullFileContent(path: String) throws -> String {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8)
        else { return "" }

        let contentLines = content.components(separatedBy: "\n")
        let count = contentLines.count
        var lines = [String]()
        lines.append("diff --git a/\(path) b/\(path)")
        lines.append("new file mode 100644")
        lines.append("--- /dev/null")
        lines.append("+++ b/\(path)")
        lines.append("@@ -0,0 +1,\(count) @@")
        for line in contentLines {
            lines.append("+\(line)")
        }
        return lines.joined(separator: "\n")
    }

    func stagedFileDiff(path: String) throws -> String {
        guard let repo else { throw GitError.repoNotOpen }

        var headTree: OpaquePointer?
        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0, let headRef {
            defer { git_reference_free(headRef) }
            var commitObj: OpaquePointer?
            if git_reference_peel(&commitObj, headRef, GIT_OBJECT_COMMIT) == 0, let commitObj {
                defer { git_object_free(commitObj) }
                git_commit_tree(&headTree, commitObj)
            }
        }
        defer { if let headTree { git_tree_free(headTree) } }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else { return "" }
        defer { git_index_free(index) }

        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        let cPath = strdup(path)
        defer { free(cPath) }
        var pathPtr: UnsafeMutablePointer<CChar>? = cPath
        opts.pathspec = withUnsafeMutablePointer(to: &pathPtr) { ptr in
            git_strarray(strings: ptr, count: 1)
        }

        var diff: OpaquePointer?
        guard git_diff_tree_to_index(&diff, repo, headTree, index, &opts) == 0, let diff else { return "" }
        defer { git_diff_free(diff) }

        var buf = git_buf()
        guard git_diff_to_buf(&buf, diff, GIT_DIFF_FORMAT_PATCH) == 0 else { return "" }
        defer { git_buf_dispose(&buf) }
        return String(cString: buf.ptr)
    }

    func unstagedFileDiff(path: String) throws -> String {
        guard let repo else { throw GitError.repoNotOpen }

        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        let cPath = strdup(path)
        defer { free(cPath) }
        var pathPtr: UnsafeMutablePointer<CChar>? = cPath
        opts.pathspec = withUnsafeMutablePointer(to: &pathPtr) { ptr in
            git_strarray(strings: ptr, count: 1)
        }

        var diff: OpaquePointer?
        guard git_diff_index_to_workdir(&diff, repo, nil, &opts) == 0, let diff else { return "" }
        defer { git_diff_free(diff) }

        var buf = git_buf()
        guard git_diff_to_buf(&buf, diff, GIT_DIFF_FORMAT_PATCH) == 0 else { return "" }
        defer { git_buf_dispose(&buf) }
        return String(cString: buf.ptr)
    }

    func fileDiff(hash: String, path: String) throws -> String {
        guard let diff = treeDiff(hash: hash) else { return "" }
        defer { git_diff_free(diff) }

        let numDeltas = git_diff_num_deltas(diff)
        for i in 0..<numDeltas {
            guard let delta = git_diff_get_delta(diff, i) else { continue }
            let filePath = delta.pointee.new_file.path.map(String.init(cString:)) ?? ""
            guard filePath == path else { continue }

            var patch: OpaquePointer?
            guard git_patch_from_diff(&patch, diff, i) == 0, let patch else { return "" }
            defer { git_patch_free(patch) }

            var buf = git_buf()
            guard git_patch_to_buf(&buf, patch) == 0 else { return "" }
            defer { git_buf_dispose(&buf) }
            return String(cString: buf.ptr)
        }
        return ""
    }

    // MARK: - Status

    func status() throws -> [FileStatus] {
        guard let repo else { throw GitError.repoNotOpen }

        var opts = git_status_options()
        git_status_options_init(&opts, UInt32(GIT_STATUS_OPTIONS_VERSION))
        opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue |
                     GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue |
                     GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue |
                     GIT_STATUS_OPT_SORT_CASE_SENSITIVELY.rawValue

        var statusList: OpaquePointer?
        guard git_status_list_new(&statusList, repo, &opts) == 0, let statusList else { return [] }
        defer { git_status_list_free(statusList) }

        var result: [FileStatus] = []
        let count = git_status_list_entrycount(statusList)

        for i in 0..<count {
            guard let entry = git_status_byindex(statusList, i) else { continue }
            let flags = entry.pointee.status

            let path: String
            if let d = entry.pointee.head_to_index {
                path = d.pointee.new_file.path.map(String.init(cString:)) ?? ""
            } else if let d = entry.pointee.index_to_workdir {
                path = d.pointee.new_file.path.map(String.init(cString:)) ?? ""
            } else {
                continue
            }

            let code = statusCodeFromFlags(flags.rawValue)
            result.append(FileStatus(statusCode: code, path: path))
        }
        return result
    }

    private nonisolated func statusCodeFromFlags(_ flags: UInt32) -> String {
        let idx: Character
        if flags & GIT_STATUS_INDEX_NEW.rawValue != 0 { idx = "A" }
        else if flags & GIT_STATUS_INDEX_MODIFIED.rawValue != 0 { idx = "M" }
        else if flags & GIT_STATUS_INDEX_DELETED.rawValue != 0 { idx = "D" }
        else if flags & GIT_STATUS_INDEX_RENAMED.rawValue != 0 { idx = "R" }
        else { idx = " " }

        let wt: Character
        if flags & GIT_STATUS_WT_NEW.rawValue != 0 { wt = "?" }
        else if flags & GIT_STATUS_WT_MODIFIED.rawValue != 0 { wt = "M" }
        else if flags & GIT_STATUS_WT_DELETED.rawValue != 0 { wt = "D" }
        else if flags & GIT_STATUS_WT_RENAMED.rawValue != 0 { wt = "R" }
        else { wt = " " }

        if flags & GIT_STATUS_WT_NEW.rawValue != 0 && idx == " " {
            return "??"
        }
        return "\(idx)\(wt)"
    }

    // MARK: - Staging

    func stageFile(_ path: String) throws {
        guard let repo else { throw GitError.repoNotOpen }
        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else {
            throw GitError.operationFailed("Cannot get index")
        }
        defer { git_index_free(index) }

        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        let fileExists = FileManager.default.fileExists(atPath: fullPath)

        if fileExists {
            git_index_add_bypath(index, path)
        } else {
            git_index_remove_bypath(index, path)
        }
        git_index_write(index)
    }

    func unstageFile(_ path: String) throws {
        guard let repo else { throw GitError.repoNotOpen }

        var headRef: OpaquePointer?
        let hasHead = git_repository_head(&headRef, repo) == 0

        if hasHead, let headRef {
            defer { git_reference_free(headRef) }
            var target: OpaquePointer?
            guard git_reference_peel(&target, headRef, GIT_OBJECT_COMMIT) == 0, let target else { return }
            defer { git_object_free(target) }

            let cPath = strdup(path)
            defer { free(cPath) }
            var pathPtr: UnsafeMutablePointer<CChar>? = cPath
            withUnsafeMutablePointer(to: &pathPtr) { strings in
                var pathSpec = git_strarray(strings: strings, count: 1)
                git_reset_default(repo, target, &pathSpec)
            }
        } else {
            var index: OpaquePointer?
            guard git_repository_index(&index, repo) == 0, let index else {
                throw GitError.operationFailed("Cannot get index")
            }
            defer { git_index_free(index) }
            git_index_remove_bypath(index, path)
            git_index_write(index)
        }
    }

    // MARK: - Fetch / Pull / Push (shell-based, following Xit's approach for reliability)

    func fetch(remoteName: String? = nil) async throws {
        var args = ["fetch"]
        if let remoteName {
            args.append(remoteName)
        } else {
            args.append("--all")
        }
        try await runGit(args)
    }

    func pull(remoteName: String? = nil, branchName: String? = nil) async throws {
        var args = ["pull"]
        if let remoteName {
            args.append(remoteName)
            if let branchName { args.append(branchName) }
        }
        try await runGit(args)
    }

    func push(remoteName: String? = nil, branchName: String? = nil, setUpstream: Bool = false) async throws {
        var args = ["push"]
        if setUpstream { args.append("-u") }
        if let remoteName {
            args.append(remoteName)
            if let branchName { args.append(branchName) }
        } else {
            args.append(contentsOf: ["-u", "origin", "HEAD"])
        }
        try await runGit(args)
    }

    // MARK: - Branch Creation

    func createBranch(name: String, checkout: Bool = true) async throws {
        if checkout {
            try await runGit(["checkout", "-b", name])
        } else {
            try await runGit(["branch", name])
        }
    }

    func createBranchAt(name: String, commitHash: String) async throws {
        try await runGit(["branch", name, commitHash])
    }

    func checkoutBranch(_ name: String) async throws {
        try await runGit(["checkout", name])
    }

    func checkoutCommit(_ hash: String) async throws {
        try await runGit(["checkout", hash])
    }

    func merge(_ branchOrHash: String) async throws {
        try await runGit(["merge", branchOrHash])
    }

    func rebase(onto target: String) async throws {
        try await runGit(["rebase", target])
    }

    func cherryPick(_ hash: String) async throws {
        try await runGit(["cherry-pick", hash])
    }

    func resetToCommit(_ hash: String, mode: ResetMode) async throws {
        try await runGit(["reset", mode.flag, hash])
    }

    func revertCommit(_ hash: String) async throws {
        try await runGit(["revert", "--no-edit", hash])
    }

    func deleteBranch(_ name: String, force: Bool = false) async throws {
        try await runGit(["branch", force ? "-D" : "-d", name])
    }

    func renameBranch(oldName: String, newName: String) async throws {
        try await runGit(["branch", "-m", oldName, newName])
    }

    func deleteRemoteBranch(remote: String, branch: String) async throws {
        try await runGit(["push", remote, "--delete", branch])
    }

    func createTag(name: String, at hash: String, message: String? = nil) async throws {
        if let message {
            try await runGit(["tag", "-a", name, hash, "-m", message])
        } else {
            try await runGit(["tag", name, hash])
        }
    }

    func setUpstream(remote: String, branch: String) async throws {
        try await runGit(["branch", "--set-upstream-to=\(remote)/\(branch)"])
    }

    func editCommitMessage(_ hash: String, newMessage: String) async throws {
        try await runGit(["rebase", "-i", "--autosquash", "\(hash)^"])
    }

    func amendCommitMessage(_ newMessage: String) async throws {
        try await runGit(["commit", "--amend", "-m", newMessage])
    }

    func compareWithWorkingDirectory(_ hash: String) async throws -> String {
        try await runGitOutput(["diff", hash])
    }

    func compareFileList(_ hash: String) async throws -> [DiffFile] {
        let raw = try await runGitOutput(["diff", "--numstat", hash])
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { return nil }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = String(parts[2])
            return DiffFile(additions: adds, deletions: dels, path: path)
        }
    }

    func compareFileDiff(_ hash: String, path: String) async throws -> String {
        try await runGitOutput(["diff", hash, "--", path])
    }

    enum ResetMode: String {
        case soft, mixed, hard
        var flag: String { "--\(rawValue)" }
        var displayName: String { rawValue.capitalized }
    }

    // MARK: - Remote Management

    func addRemote(name: String, url: String) async throws {
        try await runGit(["remote", "add", name, url])
    }

    func deleteRemote(name: String) async throws {
        try await runGit(["remote", "remove", name])
    }

    func renameRemote(oldName: String, newName: String) async throws {
        try await runGit(["remote", "rename", oldName, newName])
    }

    func setRemoteURL(name: String, url: String) async throws {
        try await runGit(["remote", "set-url", name, url])
    }

    // MARK: - Stash (libgit2, following Xit's XTRepository+Commands.swift)

    func stashSave(message: String?, includeUntracked: Bool = true) throws {
        guard let repo else { throw GitError.repoNotOpen }

        guard let sig = makeDefaultSignature(repo: repo) else {
            throw GitError.operationFailed("No git user configured. Run: git config --global user.name \"Name\" && git config --global user.email \"email\"")
        }
        defer { git_signature_free(sig) }

        var flags: UInt32 = 0
        if includeUntracked {
            flags |= GIT_STASH_INCLUDE_UNTRACKED.rawValue
        }

        var oid = git_oid()
        let rc = git_stash_save(&oid, repo, sig, message, flags)
        guard rc == 0 else {
            throw GitError.operationFailed("Stash save failed (\(rc))")
        }
    }

    func stashPop(index: Int = 0) throws {
        guard let repo else { throw GitError.repoNotOpen }

        var opts = git_stash_apply_options()
        git_stash_apply_options_init(&opts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))
        opts.flags = GIT_STASH_APPLY_REINSTATE_INDEX.rawValue

        let rc = git_stash_pop(repo, index, &opts)
        guard rc == 0 else {
            throw GitError.operationFailed("Stash pop failed (\(rc))")
        }
    }

    func stashApply(index: Int = 0) throws {
        guard let repo else { throw GitError.repoNotOpen }

        var opts = git_stash_apply_options()
        git_stash_apply_options_init(&opts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))
        opts.flags = GIT_STASH_APPLY_REINSTATE_INDEX.rawValue

        let rc = git_stash_apply(repo, index, &opts)
        guard rc == 0 else {
            throw GitError.operationFailed("Stash apply failed (\(rc))")
        }
    }

    func stashDrop(index: Int = 0) throws {
        guard let repo else { throw GitError.repoNotOpen }

        let rc = git_stash_drop(repo, index)
        guard rc == 0 else {
            throw GitError.operationFailed("Stash drop failed (\(rc))")
        }
    }

    // MARK: - Git CLI helper

    private func runGit(_ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = args
            proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            let pipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                    continuation.resume(throwing: GitError.operationFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runGitOutput(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = args
            proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            let pipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                    continuation.resume(throwing: GitError.operationFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Patch Application (for hunk/line staging & discarding)

    /// Apply a patch string via `git apply`.
    /// - cached: stage the patch (apply to index)
    /// - reverse: apply in reverse (for discarding changes)
    func applyPatch(_ patch: String, cached: Bool = false, reverse: Bool = false) async throws {
        var args = ["apply", "--unidiff-zero", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args.append("-")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = args
            proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)

            let inputPipe = Pipe()
            let errPipe = Pipe()
            proc.standardInput = inputPipe
            proc.standardOutput = Pipe()
            proc.standardError = errPipe

            do {
                try proc.run()
                if let data = patch.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                inputPipe.fileHandleForWriting.closeFile()
                proc.waitUntilExit()

                if proc.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "git apply failed"
                    continuation.resume(throwing: GitError.operationFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - File Actions

    func discardFileChanges(path: String) async throws {
        try await runGit(["checkout", "--", path])
    }

    func addToGitignore(pattern: String) async throws {
        let gitignorePath = (repoPath as NSString).appendingPathComponent(".gitignore")
        let fm = FileManager.default

        var existing = ""
        if fm.fileExists(atPath: gitignorePath),
           let data = fm.contents(atPath: gitignorePath),
           let str = String(data: data, encoding: .utf8) {
            existing = str
        }

        let newContent: String
        if existing.hasSuffix("\n") || existing.isEmpty {
            newContent = existing + pattern + "\n"
        } else {
            newContent = existing + "\n" + pattern + "\n"
        }
        try newContent.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Rebase Conflict Detection & Resolution

    func isRebaseInProgress() -> Bool {
        guard let repo else { return false }
        let state = git_repository_state(repo)
        return state == GIT_REPOSITORY_STATE_REBASE_MERGE.rawValue
            || state == GIT_REPOSITORY_STATE_REBASE_INTERACTIVE.rawValue
            || state == GIT_REPOSITORY_STATE_REBASE.rawValue
    }

    func rebaseState() throws -> RebaseState? {
        guard isRebaseInProgress() else { return nil }
        let fm = FileManager.default
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")

        var rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-merge")
        if !fm.fileExists(atPath: rebaseDir) {
            rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-apply")
            if !fm.fileExists(atPath: rebaseDir) { return nil }
        }

        let headName = (try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("head-name"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "") ?? "unknown"

        let ontoHash = (try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("onto"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let targetBranch = branchNameForHash(ontoHash) ?? String(ontoHash.prefix(7))

        let msgNum = Int((try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("msgnum"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "1") ?? 1
        let endNum = Int((try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("end"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "1") ?? 1

        let conflicted = try conflictedFiles()
        let resolved = try resolvedConflictFiles()

        return RebaseState(
            sourceBranch: headName,
            targetBranch: targetBranch,
            currentStep: msgNum,
            totalSteps: endNum,
            conflictedFiles: conflicted,
            resolvedFiles: resolved
        )
    }

    private func branchNameForHash(_ hash: String) -> String? {
        guard let repo, !hash.isEmpty else { return nil }
        var iter: OpaquePointer?
        guard git_branch_iterator_new(&iter, repo, GIT_BRANCH_LOCAL) == 0, let iter else { return nil }
        defer { git_branch_iterator_free(iter) }

        var ref: OpaquePointer?
        var branchType = GIT_BRANCH_LOCAL
        while git_branch_next(&ref, &branchType, iter) == 0, let ref {
            defer { git_reference_free(ref) }
            if let oid = git_reference_target(ref) {
                let refHash = oidToHash(oid)
                if refHash.hasPrefix(hash) || hash.hasPrefix(refHash.prefix(7).description) {
                    var nameC: UnsafePointer<CChar>?
                    git_branch_name(&nameC, ref)
                    return nameC.map(String.init(cString:))
                }
            }
        }
        return nil
    }

    func conflictedFiles() throws -> [ConflictFile] {
        guard let repo else { throw GitError.repoNotOpen }
        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else { return [] }
        defer { git_index_free(index) }

        guard git_index_has_conflicts(index) == 1 else { return [] }

        var iter: OpaquePointer?
        guard git_index_conflict_iterator_new(&iter, index) == 0, let iter else { return [] }
        defer { git_index_conflict_iterator_free(iter) }

        var result: [ConflictFile] = []
        var ancestor: UnsafePointer<git_index_entry>?
        var ours: UnsafePointer<git_index_entry>?
        var theirs: UnsafePointer<git_index_entry>?

        while git_index_conflict_next(&ancestor, &ours, &theirs, iter) == 0 {
            let path: String
            if let ours, let p = ours.pointee.path {
                path = String(cString: p)
            } else if let theirs, let p = theirs.pointee.path {
                path = String(cString: p)
            } else {
                continue
            }

            let fullPath = (repoPath as NSString).appendingPathComponent(path)
            var conflictCount = 0
            if let data = FileManager.default.contents(atPath: fullPath),
               let content = String(data: data, encoding: .utf8) {
                conflictCount = content.components(separatedBy: "<<<<<<<").count - 1
            }
            result.append(ConflictFile(path: path, conflictCount: max(conflictCount, 1)))
        }
        return result
    }

    private func resolvedConflictFiles() throws -> [ConflictFile] {
        []
    }

    func readConflictSides(path: String) throws -> ConflictSides {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8)
        else { throw GitError.operationFailed("Cannot read file") }

        let oursLabel = conflictOursLabel()
        let theirsLabel = conflictTheirsLabel()
        let lines = content.components(separatedBy: "\n")

        var oursLines: [String] = []
        var theirsLines: [String] = []
        var regions: [ConflictRegion] = []
        var inConflict = false
        var inOurs = false
        var currentOursStart = 0
        var currentTheirsStart = 0
        var regionId = 0
        var baseStart = 0

        for line in lines {
            if line.hasPrefix("<<<<<<<") {
                inConflict = true
                inOurs = true
                currentOursStart = oursLines.count
                currentTheirsStart = theirsLines.count
                baseStart = oursLines.count
                continue
            }
            if line.hasPrefix("=======") && inConflict {
                inOurs = false
                continue
            }
            if line.hasPrefix(">>>>>>>") && inConflict {
                inConflict = false
                regions.append(ConflictRegion(
                    id: regionId,
                    oursRange: currentOursStart..<oursLines.count,
                    theirsRange: currentTheirsStart..<theirsLines.count,
                    baseRange: baseStart..<max(oursLines.count, theirsLines.count)
                ))
                regionId += 1

                let ourCount = oursLines.count - currentOursStart
                let theirCount = theirsLines.count - currentTheirsStart
                if ourCount < theirCount {
                    for _ in 0..<(theirCount - ourCount) { oursLines.append("") }
                } else if theirCount < ourCount {
                    for _ in 0..<(ourCount - theirCount) { theirsLines.append("") }
                }
                continue
            }

            if inConflict {
                if inOurs {
                    oursLines.append(line)
                } else {
                    theirsLines.append(line)
                }
            } else {
                oursLines.append(line)
                theirsLines.append(line)
            }
        }

        return ConflictSides(
            oursLabel: oursLabel,
            theirsLabel: theirsLabel,
            oursContent: oursLines.joined(separator: "\n"),
            theirsContent: theirsLines.joined(separator: "\n"),
            markers: regions
        )
    }

    private func conflictOursLabel() -> String {
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        let rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-merge")
        let ontoHash = (try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("onto"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch = branchNameForHash(ontoHash) ?? String(ontoHash.prefix(7))
        let shortHash = String(ontoHash.prefix(7))
        return "Commit \(shortHash) on \(branch)"
    }

    private func conflictTheirsLabel() -> String {
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        let rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-merge")
        let headName = (try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("head-name"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "refs/heads/", with: "") ?? "unknown"
        let origHead = (try? String(contentsOfFile: (rebaseDir as NSString).appendingPathComponent("orig-head"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shortHash = String(origHead.prefix(7))
        return "Commit \(shortHash) on \(headName)"
    }

    func markConflictResolved(path: String) async throws {
        try stageFile(path)
    }

    func markAllConflictsResolved() async throws {
        let files = try conflictedFiles()
        for file in files {
            try stageFile(file.path)
        }
    }

    func rebaseCommitMessage() -> String {
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        let rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-merge")
        let msgPath = (rebaseDir as NSString).appendingPathComponent("message")
        return (try? String(contentsOfFile: msgPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func rebaseContinue(message: String? = nil) async throws {
        if let message, !message.isEmpty {
            let gitDir = (repoPath as NSString).appendingPathComponent(".git")
            let rebaseDir = (gitDir as NSString).appendingPathComponent("rebase-merge")
            let msgPath = (rebaseDir as NSString).appendingPathComponent("message")
            try? message.write(toFile: msgPath, atomically: true, encoding: .utf8)
        }
        try await runGit(["rebase", "--continue"])
    }

    func rebaseSkip() async throws {
        try await runGit(["rebase", "--skip"])
    }

    func rebaseAbort() async throws {
        try await runGit(["rebase", "--abort"])
    }

    func saveConflictResolution(path: String, content: String) throws {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
    }

    // MARK: - SSH Host Key

    func addHostToKnownHosts(host: String) async throws {
        let sshDir = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
        let knownHostsPath = (sshDir as NSString).appendingPathComponent("known_hosts")

        let fm = FileManager.default
        if !fm.fileExists(atPath: sshDir) {
            try fm.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keyscan")
        proc.arguments = ["-H", host]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw GitError.operationFailed("ssh-keyscan returned no keys for \(host)")
        }

        if let fh = FileHandle(forWritingAtPath: knownHostsPath) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            fm.createFile(atPath: knownHostsPath, contents: data)
        }
    }

    // MARK: - HEAD Commit Message (for amend)

    func headCommitMessage() throws -> String {
        guard let repo else { throw GitError.repoNotOpen }
        var head: OpaquePointer?
        guard git_repository_head(&head, repo) == 0, let head else { return "" }
        defer { git_reference_free(head) }
        guard let oid = git_reference_target(head) else { return "" }
        var commit: OpaquePointer?
        guard git_commit_lookup(&commit, repo, oid) == 0, let commit else { return "" }
        defer { git_commit_free(commit) }
        return git_commit_message(commit).map(String.init(cString:))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Commit

    func commitAmend(message: String) async throws {
        try await runGit(["commit", "--amend", "-m", message])
    }

    func commit(message: String) throws {
        guard let repo else { throw GitError.repoNotOpen }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else {
            throw GitError.operationFailed("Cannot get index")
        }
        defer { git_index_free(index) }

        var treeOid = git_oid()
        guard git_index_write_tree(&treeOid, index) == 0 else {
            throw GitError.operationFailed("Write tree failed")
        }
        guard git_index_write(index) == 0 else {
            throw GitError.operationFailed("Index write failed")
        }

        var tree: OpaquePointer?
        guard git_tree_lookup(&tree, repo, &treeOid) == 0, let tree else {
            throw GitError.operationFailed("Tree lookup failed")
        }
        defer { git_tree_free(tree) }

        guard let sig = makeDefaultSignature(repo: repo) else {
            throw GitError.operationFailed("No git user configured. Run: git config --global user.name \"Name\" && git config --global user.email \"email\"")
        }
        defer { git_signature_free(sig) }

        var parentCommit: OpaquePointer?
        var headRef: OpaquePointer?
        if git_repository_head(&headRef, repo) == 0, let headRef {
            defer { git_reference_free(headRef) }
            if let oid = git_reference_target(headRef) {
                git_commit_lookup(&parentCommit, repo, oid)
            }
        }
        defer { if let parentCommit { git_commit_free(parentCommit) } }

        var commitOid = git_oid()
        let rc: Int32
        if let parentCommit {
            var parent: OpaquePointer? = parentCommit
            rc = git_commit_create(
                &commitOid, repo, "HEAD", sig, sig,
                nil, message, tree, 1, &parent
            )
        } else {
            rc = git_commit_create(
                &commitOid, repo, "HEAD", sig, sig,
                nil, message, tree, 0, nil
            )
        }

        guard rc == 0 else {
            throw GitError.operationFailed("Commit failed (\(rc))")
        }
    }
}

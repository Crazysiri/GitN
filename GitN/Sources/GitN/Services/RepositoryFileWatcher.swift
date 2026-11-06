import Foundation
import CoreServices

/// Watches a git repository's `.git/` directory and working tree for filesystem
/// changes, then fires a callback so the UI can refresh.
///
/// Modeled after PBGitRepositoryWatcher (refs/gitx) and RepositoryWatcher
/// (refs/Xit):
///   - Uses FSEventStream to monitor both `.git/` (index, HEAD, refs) and the
///     working directory (file edits, new/deleted files).
///   - Coalesces rapid events with a debounce timer to avoid hammering git.
///   - Ignores `.git/objects` (pack files churn) and `.lock` files (transient).
final class RepositoryFileWatcher {
    enum ChangeKind: Hashable {
        case index
        case head
        case refs
        case worktrees
        case workingDirectory
    }

    private let commonDirPath: String
    private let metadataPaths: GitRepositoryMetadataPaths
    private let onChange: (Set<ChangeKind>) -> Void

    private var stream: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    private var pendingChanges = Set<ChangeKind>()
    private let queue = DispatchQueue(label: "com.gitx.fswatcher", qos: .utility)

    /// - Parameters:
    ///   - repoPath: The working-tree root (e.g. `/Users/me/project`).
    ///   - onChange: Called on the **main thread** with the set of change kinds
    ///     detected since the last callback.
    init(repoPath: String, onChange: @escaping (Set<ChangeKind>) -> Void) {
        let paths = GitRepositoryMetadataPaths(repoPath: repoPath)
        self.commonDirPath = paths.commonDirPath
        self.metadataPaths = paths
        self.onChange = onChange
        startWatching()
    }

    deinit {
        stop()
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - FSEventStream Setup

    private func startWatching() {
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var context = FSEventStreamContext(
            version: 0, info: selfPtr,
            retain: nil, release: nil, copyDescription: nil
        )

        let paths = metadataPaths.watchPaths as CFArray
        let objectsPath = (commonDirPath as NSString).appendingPathComponent("objects")

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, eventFlags, _) in
            guard let clientInfo else { return }
            let watcher = Unmanaged<RepositoryFileWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
            else { return }
            watcher.handleEvents(cfPaths, flags: eventFlags, count: numEvents)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        FSEventStreamSetExclusionPaths(stream, [objectsPath] as CFArray)
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    // MARK: - Event Handling

    private func handleEvents(_ paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, count: Int) {
        var changes = Set<ChangeKind>()

        for i in 0..<count {
            let path = (paths[i] as NSString).standardizingPath
            changes.formUnion(Self.changeKinds(for: path, metadataPaths: metadataPaths))
        }

        guard !changes.isEmpty else { return }
        pendingChanges.formUnion(changes)
        scheduleDebouncedNotification()
    }

    /// Classify against the real per-worktree gitdir before the common gitdir:
    /// the former can be nested inside the latter for linked worktrees.
    static func changeKinds(
        for path: String,
        metadataPaths: GitRepositoryMetadataPaths
    ) -> Set<ChangeKind> {
        let path = (path as NSString).standardizingPath
        if path.hasSuffix(".lock") { return [] }

        if let relative = GitRepositoryMetadataPaths.relativePath(path, inside: metadataPaths.gitDirPath) {
            if relative.isEmpty { return [.head, .refs, .index] }
            if relative == "worktrees" || relative.hasPrefix("worktrees/") { return [.worktrees] }
            if relative == "index" { return [.index] }
            if relative == "HEAD" || ["MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD"].contains(relative) {
                return [.head]
            }
            if relative == "packed-refs" || relative == "refs" || relative.hasPrefix("refs/") {
                return [.refs]
            }
            if relative == "config" { return [.refs] }
            return []
        }

        if let relative = GitRepositoryMetadataPaths.relativePath(path, inside: metadataPaths.commonDirPath) {
            if relative.isEmpty { return [.refs] }
            if relative == "worktrees" || relative.hasPrefix("worktrees/") { return [.worktrees] }
            if relative == "packed-refs" || relative == "refs" || relative.hasPrefix("refs/") {
                return [.refs]
            }
            if relative == "config" { return [.refs] }
            return []
        }

        if let relative = GitRepositoryMetadataPaths.relativePath(path, inside: metadataPaths.workTreePath) {
            if relative == ".git" { return [.head, .refs, .index] }
            return [.workingDirectory]
        }
        return []
    }

    private func scheduleDebouncedNotification() {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.flushPendingChanges()
        }
        timer.resume()
        debounceTimer = timer
    }

    private func flushPendingChanges() {
        let changes = pendingChanges
        pendingChanges.removeAll()
        guard !changes.isEmpty else { return }
        DispatchQueue.main.async { [onChange] in
            onChange(changes)
        }
    }
}

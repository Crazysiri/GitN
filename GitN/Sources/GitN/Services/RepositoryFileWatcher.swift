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
        case workingDirectory
    }

    private let repoPath: String
    private let gitDirPath: String
    private let onChange: (Set<ChangeKind>) -> Void

    private var stream: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    private var pendingChanges = Set<ChangeKind>()
    private let queue = DispatchQueue(label: "com.gitx.fswatcher", qos: .utility)
    private var lastIndexModDate: Date?

    /// - Parameters:
    ///   - repoPath: The working-tree root (e.g. `/Users/me/project`).
    ///   - onChange: Called on the **main thread** with the set of change kinds
    ///     detected since the last callback.
    init(repoPath: String, onChange: @escaping (Set<ChangeKind>) -> Void) {
        self.repoPath = (repoPath as NSString).standardizingPath
        self.gitDirPath = (repoPath as NSString).appendingPathComponent(".git")
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
        lastIndexModDate = indexModificationDate()

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var context = FSEventStreamContext(
            version: 0, info: selfPtr,
            retain: nil, release: nil, copyDescription: nil
        )

        let paths = [repoPath, gitDirPath] as CFArray
        let objectsPath = (gitDirPath as NSString).appendingPathComponent("objects")

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, eventFlags, _) in
            guard let clientInfo else { return }
            let watcher = Unmanaged<RepositoryFileWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
            else { return }
            watcher.handleEvents(cfPaths, flags: eventFlags, count: numEvents)
        }

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )!

        FSEventStreamSetExclusionPaths(stream, [objectsPath] as CFArray)
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    // MARK: - Event Handling

    private func handleEvents(_ paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, count: Int) {
        var changes = Set<ChangeKind>()

        for i in 0..<count {
            let path = (paths[i] as NSString).standardizingPath

            if path.hasSuffix(".lock") { continue }

            if path.hasPrefix(gitDirPath) {
                if path.contains("/objects/") { continue }

                let relative = String(path.dropFirst(gitDirPath.count + 1))

                if relative == "index" || relative.hasPrefix("index") {
                    if indexDidChange() {
                        changes.insert(.index)
                    }
                } else if relative == "HEAD" {
                    changes.insert(.head)
                } else if relative.hasPrefix("refs/") {
                    changes.insert(.refs)
                } else if relative == "packed-refs" {
                    changes.insert(.refs)
                } else if relative == "MERGE_HEAD" || relative == "REBASE_HEAD"
                            || relative == "CHERRY_PICK_HEAD" {
                    changes.insert(.head)
                }
            } else if path.hasPrefix(repoPath) {
                changes.insert(.workingDirectory)
            }
        }

        guard !changes.isEmpty else { return }
        pendingChanges.formUnion(changes)
        scheduleDebouncedNotification()
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

    // MARK: - Index Helpers

    private func indexModificationDate() -> Date? {
        let indexPath = (gitDirPath as NSString).appendingPathComponent("index")
        let attrs = try? FileManager.default.attributesOfItem(atPath: indexPath)
        return attrs?[.modificationDate] as? Date
    }

    private func indexDidChange() -> Bool {
        let newDate = indexModificationDate()
        if newDate != lastIndexModDate {
            lastIndexModDate = newDate
            return true
        }
        return false
    }
}

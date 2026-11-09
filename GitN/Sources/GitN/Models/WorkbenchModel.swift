import Foundation

@MainActor @Observable
final class WorkbenchModel {
    let path: String
    let commonDirectory: String
    private let store: WorkbenchTaskStore
    private let changesService = WorkbenchChangesService()
    private let resolver = SessionDirectoryResolver()
    private let inbox: SessionHookInbox
    var sessions: [WorkbenchSession] = []
    var memberships: [SessionTaskMembership] = []
    var selectedSessionID: UUID?
    var includeUnassociatedSessions = true
    var isDiscovering = false
    var discoveryMessage: String?
    var isImportingEvents = false
    var tasks: [WorkbenchTask] = []
    var worktrees: [WorktreeInfo] = []
    var selectedTaskID: UUID?
    var selectedWorktreePath: String?
    var changes: WorkbenchChanges?
    var changesError: String?
    var showsTaskChanges = false
    var error: String?
    var isLoading = false
    var isSaving = false
    var refreshedAt: Date?
    private var changeRequest = UUID()

    init(path: String, store: WorkbenchTaskStore = .shared, inbox: SessionHookInbox = SessionHookInbox()) {
        self.path = path
        self.store = store
        self.inbox = inbox
        commonDirectory = WorktreeService.canonicalPath(GitRepositoryMetadataPaths(repoPath: path).commonDirPath)
    }

    var selectedTask: WorkbenchTask? { tasks.first { $0.id == selectedTaskID } }
    var selectedLink: TaskWorktreeLink? {
        selectedTask?.worktrees.first { $0.path == selectedWorktreePath } ?? selectedTask?.worktrees.first
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedTasks = store.tasks(commonDirectory: commonDirectory)
            async let loadedWorktrees = WorktreeService(repoPath: path).list()
            let result = try await (loadedTasks, loadedWorktrees)
            tasks = result.0
            worktrees = result.1
            if !tasks.contains(where: { $0.id == selectedTaskID }) { selectedTaskID = tasks.first?.id }
            await importSessionEvents()
            await refreshSessions()
            refreshedAt = Date()
            await loadChanges()
        } catch { self.error = error.localizedDescription }
    }

    var selectedSession: WorkbenchSession? { sessions.first { $0.id == selectedSessionID } }
    var hookSetup: SessionHookSetup { SessionHookSetup(repoPath: path) }

    func refreshSessions() async {
        do {
            let snapshot = try await store.sessionSnapshot(commonDirectory: commonDirectory, includeUnassociated: includeUnassociatedSessions)
            sessions = snapshot.sessions
            memberships = snapshot.memberships
            if !sessions.contains(where: { $0.id == selectedSessionID }) { selectedSessionID = sessions.first?.id }
        } catch { self.error = error.localizedDescription }
    }

    func importSessionEvents() async {
        guard !isImportingEvents else { return }
        isImportingEvents = true
        defer { isImportingEvents = false }
        do {
            // Worktrees can be created in external tools while this page stays open.
            // This only lists Git metadata; it does not assign new directories to sessions.
            if let discovered = try? await WorktreeService(repoPath: path).list() { worktrees = discovered }
            for item in try inbox.pending() {
                let observation = try item.event.observation()
                let association = await resolver.resolve(observation.cwd, at: observation.observedAt)
                try await store.ingest(observation, association: association)
                try inbox.acknowledge(item)
            }
            await refreshSessions()
        } catch { self.error = error.localizedDescription }
    }

    func discoverCodex() async {
        guard !isDiscovering else { return }
        guard let executable = CodexSessionDiscovery.installedExecutable() else {
            discoveryMessage = "Codex CLI not found. Install it or configure Hooks to report sessions."
            return
        }
        isDiscovering = true
        defer { isDiscovering = false }
        do {
            worktrees = try await WorktreeService(repoPath: path).list()
            let discovered = try await CodexSessionDiscovery(executable: executable, namespace: hookSetup.namespace(.codex)).discover()
            var count = 0
            for observation in discovered {
                // Avoid resolving or importing unrelated repositories' conversations.
                if let cwd = observation.cwd {
                    let canonical = WorktreeService.canonicalPath(cwd)
                    guard worktrees.contains(where: {
                        let root = WorktreeService.canonicalPath($0.path)
                        return canonical == root || canonical.hasPrefix(root + "/")
                    }) else { continue }
                }
                let association = await resolver.resolve(observation.cwd, at: observation.observedAt)
                try await store.ingest(observation, association: association)
                count += 1
            }
            discoveryMessage = "Read \(count) session(s) for this repository or without a directory. No Agent turn was started."
            await refreshSessions()
        } catch { discoveryMessage = error.localizedDescription }
    }

    func associateSession(_ session: WorkbenchSession, worktree: WorktreeInfo) async {
        guard let association = await resolver.resolve(worktree.path, at: Date(), source: .manual),
              association.commonDirectory == commonDirectory else {
            error = "Worktree is unavailable or belongs to another repository. Refresh and retry."
            return
        }
        do { try await store.associateSession(id: session.id, association: association); await refreshSessions() }
        catch { self.error = error.localizedDescription }
    }

    func tasks(for session: WorkbenchSession) -> [WorkbenchTask] {
        let ids = Set(memberships.filter { $0.sessionID == session.id }.map(\.taskID))
        return tasks.filter { ids.contains($0.id) }
    }

    func sessions(for task: WorkbenchTask) -> [WorkbenchSession] {
        let ids = Set(memberships.filter { $0.taskID == task.id }.map(\.sessionID))
        return sessions.filter { ids.contains($0.id) }
    }

    func sessions(for worktree: WorktreeInfo) -> [WorkbenchSession] {
        sessions.filter { session in session.worktrees.contains { $0.path == WorktreeService.canonicalPath(worktree.path) } }
    }

    private func sessionBaselines(_ session: WorkbenchSession) async throws -> [TaskWorktreeLink] {
        let paths = Set(session.worktrees.filter { $0.commonDirectory == commonDirectory }.map(\.path))
        var links: [TaskWorktreeLink] = []
        for path in paths.sorted() where worktrees.contains(where: { WorktreeService.canonicalPath($0.path) == path && !$0.isPrunable }) {
            links.append(try await changesService.baseline(path: path))
        }
        return links
    }

    func createTask(from session: WorkbenchSession) async -> Bool {
        do {
            let links = try await sessionBaselines(session)
            let task = try await store.createTaskFromSession(id: session.id, commonDirectory: commonDirectory, links: links)
            selectedTaskID = task.id
            await refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func addSession(_ session: WorkbenchSession, to task: WorkbenchTask) async {
        do {
            let links = try await sessionBaselines(session)
            try await store.groupSession(id: session.id, taskID: task.id, links: links)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func loadChanges() async {
        let request = UUID()
        changeRequest = request
        changes = nil
        changesError = nil
        guard showsTaskChanges else { return }
        guard let link = selectedLink else { return }
        do {
            let result = try await changesService.changes(link: link)
            guard changeRequest == request else { return }
            changes = result
        } catch {
            guard changeRequest == request else { return }
            self.changesError = error.localizedDescription
        }
    }

    func createTask(title: String, notes: String, agent: WorkbenchAgent,
                    existingPath: String?, newPath: String, branch: String) async -> Bool {
        guard !isSaving else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Enter a task title."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        var createdPath: String?
        do {
            let target: String
            if let existingPath {
                guard worktrees.contains(where: {
                    WorktreeService.canonicalPath($0.path) == WorktreeService.canonicalPath(existingPath)
                        && !$0.isBare && !$0.isPrunable
                }) else {
                    throw GitError.operationFailed("Select an available Worktree.")
                }
                target = existingPath
            } else {
                try await WorktreeService(repoPath: path).add(path: newPath, branch: branch, createBranch: true)
                target = newPath
                createdPath = newPath
            }
            let link = try await changesService.baseline(path: target)
            let task = try await store.create(commonDirectory: commonDirectory, title: title, notes: notes, agent: agent, links: [link])
            selectedTaskID = task.id
            selectedWorktreePath = link.path
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription + (createdPath.map {
                "\nWorktree created at \($0). It has been kept; associate it with a task after resolving this error."
            } ?? "")
            return false
        }
    }

    func setStage(_ stage: WorkbenchStage, task: WorkbenchTask) async {
        do { try await store.setStage(id: task.id, stage: stage); await refresh() }
        catch { self.error = error.localizedDescription }
    }

    func associate(_ worktree: WorktreeInfo, task: WorkbenchTask) async {
        do {
            let link = try await changesService.baseline(path: worktree.path)
            try await store.associate(id: task.id, link: link)
            selectedWorktreePath = link.path
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func deleteTask(_ task: WorkbenchTask) async {
        do { try await store.delete(id: task.id); await refresh() }
        catch { self.error = error.localizedDescription }
    }

    func removeWorktree(_ worktree: WorktreeInfo, openPaths: [String]) async {
        guard !openPaths.contains(where: { WorktreeService.canonicalPath($0) == WorktreeService.canonicalPath(worktree.path) }) else {
            error = "Close tabs using this Worktree before removing it."
            return
        }
        do { try await WorktreeService(repoPath: path).remove(worktree); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}

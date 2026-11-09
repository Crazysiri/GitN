import Foundation

/// All workbench tabs share this writer. Publish only after the candidate is saved.
actor WorkbenchTaskStore {
    static let shared = WorkbenchTaskStore(url: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("GitN/Workbench/tasks-v1.json"))

    private struct Project: Codable {
        let id: UUID
        let commonDirectory: String
    }
    private struct Document: Codable {
        var version = 2
        var projects: [Project] = []
        var tasks: [WorkbenchTask] = []
        var sessions: [WorkbenchSession] = []
        var memberships: [SessionTaskMembership] = []
        var receipts: [String] = []

        enum CodingKeys: String, CodingKey { case version, projects, tasks, sessions, memberships, receipts }
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            projects = try c.decode([Project].self, forKey: .projects)
            tasks = try c.decode([WorkbenchTask].self, forKey: .tasks)
            sessions = try c.decodeIfPresent([WorkbenchSession].self, forKey: .sessions) ?? []
            memberships = try c.decodeIfPresent([SessionTaskMembership].self, forKey: .memberships) ?? []
            receipts = try c.decodeIfPresent([String].self, forKey: .receipts) ?? []
        }
    }
    let url: URL

    init(url: URL) { self.url = url }

    func tasks(commonDirectory: String) throws -> [WorkbenchTask] {
        let document = try load()
        guard let project = document.projects.first(where: { $0.commonDirectory == commonDirectory }) else { return [] }
        return document.tasks.filter { $0.projectID == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func create(commonDirectory: String, title: String, notes: String, agent: WorkbenchAgent,
                links: [TaskWorktreeLink]) throws -> WorkbenchTask {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !links.isEmpty else {
            throw GitError.operationFailed("A task needs a title and at least one Worktree.")
        }
        var document = try load()
        let project: Project
        if let existing = document.projects.first(where: { $0.commonDirectory == commonDirectory }) {
            project = existing
        } else {
            project = Project(id: UUID(), commonDirectory: commonDirectory)
            document.projects.append(project)
        }
        let now = Date()
        let task = WorkbenchTask(id: UUID(), projectID: project.id, title: title, notes: notes,
                                 agent: agent, stage: .planned, worktrees: links, createdAt: now, updatedAt: now)
        document.tasks.append(task)
        try save(document)
        return task
    }

    func setStage(id: UUID, stage: WorkbenchStage) throws {
        var document = try load()
        guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
            throw GitError.operationFailed("Task no longer exists. Refresh the workbench.")
        }
        document.tasks[index].stage = stage
        document.tasks[index].updatedAt = Date()
        try save(document)
    }

    func associate(id: UUID, link: TaskWorktreeLink) throws {
        var document = try load()
        guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
            throw GitError.operationFailed("Task no longer exists. Refresh the workbench.")
        }
        // Never replace an existing baseline when re-associating a Worktree.
        guard !document.tasks[index].worktrees.contains(where: { $0.path == link.path }) else { return }
        document.tasks[index].worktrees.append(link)
        document.tasks[index].updatedAt = Date()
        try save(document)
    }

    func delete(id: UUID) throws {
        var document = try load()
        document.tasks.removeAll { $0.id == id }
        document.memberships.removeAll { $0.taskID == id }
        try save(document)
    }

    func sessionSnapshot(commonDirectory: String, includeUnassociated: Bool) throws -> WorkbenchSessionSnapshot {
        let document = try load()
        let project = document.projects.first { $0.commonDirectory == commonDirectory }
        let taskIDs = Set(document.tasks.filter { $0.projectID == project?.id }.map(\.id))
        let memberIDs = Set(document.memberships.filter { taskIDs.contains($0.taskID) }.map(\.sessionID))
        let sessions = document.sessions.filter {
            $0.worktrees.contains { $0.commonDirectory == commonDirectory } || memberIDs.contains($0.id)
                || (includeUnassociated && $0.worktrees.isEmpty)
        }.sorted { $0.lastObservedAt > $1.lastObservedAt }
        return WorkbenchSessionSnapshot(sessions: sessions, memberships: document.memberships.filter { taskIDs.contains($0.taskID) })
    }

    @discardableResult
    func ingest(_ observation: SessionObservation, association: SessionWorktreeAssociation?) throws -> UUID {
        guard !observation.externalID.isEmpty, !observation.namespace.isEmpty else {
            throw GitError.operationFailed("Session identity is missing.")
        }
        var document = try load()
        let existing = document.sessions.firstIndex {
            $0.agent == observation.agent && $0.namespace == observation.namespace && $0.externalID == observation.externalID
        }
        if let receipt = observation.receiptID, document.receipts.contains(receipt), let existing {
            return document.sessions[existing].id
        }
        let index: Int
        if let existing { index = existing } else {
            document.sessions.append(WorkbenchSession(id: UUID(), agent: observation.agent, namespace: observation.namespace,
                externalID: observation.externalID, lastObservedAt: observation.observedAt, worktrees: []))
            index = document.sessions.count - 1
        }
        var session = document.sessions[index]
        if let title = observation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           observation.observedAt >= (session.titleObservedAt ?? .distantPast) {
            session.externalTitle = title
            session.titleObservedAt = observation.observedAt
        }
        if observation.observedAt >= session.lastObservedAt {
            if let cwd = observation.cwd { session.reportedCWD = cwd }
            if let event = observation.event { session.lastEvent = event }
            session.lastObservedAt = observation.observedAt
        }
        if let association { Self.addAssociation(association, to: &session) }
        document.sessions[index] = session
        if let receipt = observation.receiptID { document.receipts.append(receipt); document.receipts = Array(document.receipts.suffix(10000)) }
        try save(document)
        return session.id
    }

    func associateSession(id: UUID, association: SessionWorktreeAssociation) throws {
        var document = try load()
        guard let index = document.sessions.firstIndex(where: { $0.id == id }) else {
            throw GitError.operationFailed("Session not found. Refresh the workbench.")
        }
        Self.addAssociation(association, to: &document.sessions[index])
        try save(document)
    }

    func groupSession(id: UUID, taskID: UUID, links: [TaskWorktreeLink]) throws {
        var document = try load()
        guard document.sessions.contains(where: { $0.id == id }),
              let taskIndex = document.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw GitError.operationFailed("Task or session not found. Refresh the workbench.")
        }
        for link in links where !document.tasks[taskIndex].worktrees.contains(where: { $0.path == link.path }) {
            document.tasks[taskIndex].worktrees.append(link)
        }
        if !document.memberships.contains(where: { $0.sessionID == id && $0.taskID == taskID }) {
            document.memberships.append(SessionTaskMembership(sessionID: id, taskID: taskID))
        }
        try save(document)
    }

    func createTaskFromSession(id: UUID, commonDirectory: String, links: [TaskWorktreeLink]) throws -> WorkbenchTask {
        var document = try load()
        guard let session = document.sessions.first(where: { $0.id == id }) else {
            throw GitError.operationFailed("Session not found. Refresh the workbench.")
        }
        let project: Project
        if let existing = document.projects.first(where: { $0.commonDirectory == commonDirectory }) { project = existing }
        else { project = Project(id: UUID(), commonDirectory: commonDirectory); document.projects.append(project) }
        let now = Date()
        let task = WorkbenchTask(id: UUID(), projectID: project.id, title: session.displayTitle, notes: "",
            agent: session.agent, stage: .planned, worktrees: links, createdAt: now, updatedAt: now)
        document.tasks.append(task)
        document.memberships.append(SessionTaskMembership(sessionID: id, taskID: task.id))
        try save(document)
        return task
    }

    private static func addAssociation(_ association: SessionWorktreeAssociation, to session: inout WorkbenchSession) {
        if let index = session.worktrees.firstIndex(where: { $0.id == association.id && $0.commonDirectory == association.commonDirectory }) {
            let old = session.worktrees[index]
            session.worktrees[index] = SessionWorktreeAssociation(path: old.path, commonDirectory: old.commonDirectory,
                source: old.source, firstObservedAt: min(old.firstObservedAt, association.firstObservedAt),
                lastObservedAt: max(old.lastObservedAt, association.lastObservedAt))
        } else { session.worktrees.append(association) }
    }

    private func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: url.path) else { return Document() }
        var document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard [1, 2].contains(document.version) else {
            throw GitError.operationFailed("Unsupported workbench data version. Existing data has been preserved.")
        }
        document.version = 2
        return document
    }

    private func save(_ document: Document) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let original = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           original["version"] as? Int == 1 {
            let backup = url.appendingPathExtension("v1-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
        }
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
    }
}

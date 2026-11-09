import Foundation

enum WorkbenchAgent: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case kiro = "Kiro"
    var id: String { rawValue }
}

enum WorkbenchStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned = "Planned"
    case working = "In Progress"
    case review = "Ready for Review"
    case complete = "Completed"
    var id: String { rawValue }
}

struct TaskWorktreeLink: Codable, Equatable, Identifiable, Sendable {
    let path: String
    let baseCommit: String?
    var id: String { path }
}

struct WorkbenchTask: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    var title: String
    var notes: String
    var agent: WorkbenchAgent
    var stage: WorkbenchStage
    var worktrees: [TaskWorktreeLink]
    let createdAt: Date
    var updatedAt: Date
}

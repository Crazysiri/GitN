import Foundation

struct SessionObservation: Sendable {
    let agent: WorkbenchAgent
    let namespace: String
    let externalID: String
    var title: String?
    var cwd: String?
    let observedAt: Date
    var event: String?
    var receiptID: String?
}

struct SessionWorktreeAssociation: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case reportedDirectory, manual }
    let path: String
    let commonDirectory: String
    let source: Source
    let firstObservedAt: Date
    var lastObservedAt: Date
    var id: String { source.rawValue + ":" + path }
}

struct WorkbenchSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let agent: WorkbenchAgent
    let namespace: String
    let externalID: String
    var externalTitle: String?
    var titleObservedAt: Date?
    var reportedCWD: String?
    var lastEvent: String?
    var lastObservedAt: Date
    var worktrees: [SessionWorktreeAssociation]

    var displayTitle: String {
        externalTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "\(agent.rawValue) · \(externalID.prefix(12))"
    }
}

struct SessionTaskMembership: Codable, Equatable, Sendable {
    let sessionID: UUID
    let taskID: UUID
}

struct WorkbenchSessionSnapshot: Sendable {
    var sessions: [WorkbenchSession]
    var memberships: [SessionTaskMembership]
}

struct SessionDirectoryResolver: Sendable {
    func resolve(_ cwd: String?, at date: Date, source: SessionWorktreeAssociation.Source = .reportedDirectory) async -> SessionWorktreeAssociation? {
        guard let cwd, cwd.hasPrefix("/"), FileManager.default.fileExists(atPath: cwd) else { return nil }
        let cli = GitCLI(repoPath: cwd)
        guard let top = try? await cli.output(["rev-parse", "--show-toplevel"]),
              let common = try? await cli.output(["rev-parse", "--path-format=absolute", "--git-common-dir"]) else { return nil }
        // Git emits one trailing newline; preserve embedded/leading filename whitespace.
        func path(_ value: String) -> String { value.hasSuffix("\n") ? String(value.dropLast()) : value }
        return SessionWorktreeAssociation(path: WorktreeService.canonicalPath(path(top)),
            commonDirectory: WorktreeService.canonicalPath(path(common)), source: source,
            firstObservedAt: date, lastObservedAt: date)
    }
}

struct SessionHookEnvelope: Codable, Sendable {
    let version: Int
    let id: String
    let agent: WorkbenchAgent
    let namespace: String
    let sessionID: String
    let cwd: String?
    let event: String
    let timestamp: Date

    func observation() throws -> SessionObservation {
        guard version == 1, !id.isEmpty, id.count <= 128, !sessionID.isEmpty, sessionID.count <= 256,
              !namespace.isEmpty, namespace.count <= 4096, event.count <= 128,
              cwd.map({ $0.hasPrefix("/") && $0.count <= 4096 }) ?? true else {
            throw GitError.operationFailed("Invalid session hook event.")
        }
        return SessionObservation(agent: agent, namespace: namespace, externalID: sessionID,
            cwd: cwd, observedAt: timestamp, event: event, receiptID: id)
    }
}

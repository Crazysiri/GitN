import Foundation

/// Process-local FIFO ownership, held across suspension in CLI-backed writes.
actor RepositoryMutationGate {
    private var owner: UUID?
    private var waiters: [(UUID, CheckedContinuation<UUID, Error>)] = []
    var pendingCount: Int { waiters.count }

    func acquire() async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if owner == nil {
                    owner = id
                    continuation.resume(returning: id)
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    func release(_ id: UUID) {
        guard owner == id else { return }
        if waiters.isEmpty {
            owner = nil
        } else {
            let next = waiters.removeFirst()
            owner = next.0
            next.1.resume(returning: next.0)
        }
    }
}

final class RepositoryMutationRegistry: @unchecked Sendable {
    static let shared = RepositoryMutationRegistry()
    private struct WeakGate { weak var value: RepositoryMutationGate? }
    private let lock = NSLock()
    private var gates: [String: WeakGate] = [:]

    func gate(repoPath: String) -> RepositoryMutationGate {
        // Discover the repo root as callers may have opened a subdirectory.
        var root = URL(fileURLWithPath: repoPath).standardizedFileURL.resolvingSymlinksInPath()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path),
              root.path != "/" {
            root.deleteLastPathComponent()
        }
        let metadata = GitRepositoryMetadataPaths(repoPath: root.path == "/" ? repoPath : root.path)
        let key = URL(fileURLWithPath: metadata.commonDirPath).standardizedFileURL
            .resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }
        if let existing = gates[key]?.value { return existing }
        gates = gates.filter { $0.value.value != nil }
        let gate = RepositoryMutationGate()
        gates[key] = WeakGate(value: gate)
        return gate
    }
}

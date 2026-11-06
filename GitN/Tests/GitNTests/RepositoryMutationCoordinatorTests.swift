import Foundation
import XCTest
@testable import GitN

final class RepositoryMutationCoordinatorTests: XCTestCase {
    private func waitForCount(_ count: Int, gate: RepositoryMutationGate) async throws {
        for _ in 0..<10_000 {
            if await gate.pendingCount == count { return }
            await Task.yield()
        }
        XCTFail("Queue did not reach expected count")
        throw CancellationError()
    }

    func testFIFOAndQueuedCancellation() async throws {
        let gate = RepositoryMutationGate()
        let first = try await gate.acquire()
        let cancelled = Task { try await gate.acquire() }
        try await waitForCount(1, gate: gate)
        let second = Task { try await gate.acquire() }
        try await waitForCount(2, gate: gate)
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled waiter acquired ownership") }
        catch is CancellationError { }
        try await waitForCount(1, gate: gate)
        let third = Task { try await gate.acquire() }
        try await waitForCount(2, gate: gate)
        await gate.release(first)
        let secondToken = try await second.value
        let remaining = await gate.pendingCount
        XCTAssertEqual(remaining, 1)
        await gate.release(secondToken)
        await gate.release(try await third.value)
    }

    func testIndependentRepositoriesAndSubdirectoryIdentity() throws {
        let a = try TemporaryGitRepository()
        let b = try TemporaryGitRepository()
        let registry = RepositoryMutationRegistry.shared
        let gate = registry.gate(repoPath: a.path)
        XCTAssertTrue(gate === registry.gate(repoPath: a.path + "/Sources/deep"))
        XCTAssertFalse(gate === registry.gate(repoPath: b.path))
    }

    func testLinkedWorktreeSharesOwnership() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let linked = repo.url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: linked) }
        try await WorktreeService(repoPath: repo.path).add(path: linked.path, branch: "linked", createBranch: true)
        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repo.path)
        XCTAssertTrue(gate === RepositoryMutationRegistry.shared.gate(repoPath: linked.path))
    }

    func testMultipleServicesWaitBeforeStagingAndRecoverAfterFailure() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("a.txt", contents: "a\n")
        try repo.writeFile("b.txt", contents: "b\n")
        let one = GitService(repoPath: repo.path)
        let two = GitService(repoPath: repo.path)
        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repo.path)
        let owner = try await gate.acquire()
        let stageOne = Task { try await one.stageFile("a.txt") }
        let stageTwo = Task { try await two.stageFile("b.txt") }
        try await waitForCount(2, gate: gate)
        XCTAssertEqual(try repo.run(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines), "")
        await gate.release(owner)
        try await stageOne.value
        try await stageTwo.value
        let staged = try repo.run(["diff", "--cached", "--name-only"])
        XCTAssertTrue(staged.contains("a.txt") && staged.contains("b.txt"))
        do { try await one.checkoutBranch("nonexistent"); XCTFail("Expected missing branch failure") }
        catch { }
        try await two.unstageFile("a.txt")
        XCTAssertEqual(try repo.run(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines), "b.txt")
    }
}

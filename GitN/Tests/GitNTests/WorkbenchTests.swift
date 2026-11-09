import Foundation
import XCTest
@testable import GitN

final class WorkbenchTests: XCTestCase {
    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GitN-workbench-\(UUID().uuidString)/tasks.json")
    }

    func testLegacyTabsAndMixedKindsDecodeWithoutChangingRecentRepositoryFormat() throws {
        let old = try JSONEncoder().encode([SavedRepo(path: "/repo", name: "repo")])
        XCTAssertEqual(TabPersistence.decode(current: nil, legacy: old), [SavedTab(path: "/repo", name: "repo", kind: .git)])
        let mixed = [SavedTab(path: "/repo", name: "repo", kind: .git), SavedTab(path: "/repo", name: "repo", kind: .workbench)]
        XCTAssertEqual(TabPersistence.decode(current: try JSONEncoder().encode(mixed), legacy: old), mixed)
        XCTAssertTrue(TabPersistence.decode(current: Data("[]".utf8), legacy: old).isEmpty)
        XCTAssertEqual(TabPersistence.decode(current: Data("broken".utf8), legacy: old).count, 1)
    }

    @MainActor
    func testMixedTabsDeduplicateWithinKindAndRestoreAcrossRestart() throws {
        let repo = try TemporaryGitRepository()
        let suite = "GitN-workbench-tabs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([SavedRepo(path: repo.path, name: "old")]), forKey: "GitN.savedRepos")
        let app = AppModel(defaults: defaults)
        XCTAssertEqual(app.tabs.map(\.kind), [.git])
        app.openWorkbench(path: repo.path, name: "test")
        app.openWorkbench(path: repo.path + "/.", name: "test")
        app.openRepository(path: repo.path, name: "test")
        XCTAssertEqual(app.tabs.map(\.kind), [.git, .workbench])
        app.moveTab(fromIndex: 1, toIndex: 0)
        let restored = AppModel(defaults: defaults)
        XCTAssertEqual(restored.tabs.map(\.kind), [.workbench, .git])
        XCTAssertEqual(restored.recentRepos.count, 1)
        restored.tabs.map(\.id).forEach { restored.closeTab($0) }
        XCTAssertTrue(AppModel(defaults: defaults).tabs.isEmpty)
        XCTAssertNotNil(defaults.data(forKey: "GitN.savedRepos"))
    }

    func testTasksPersistAcrossStoresAndKeepMultipleBaselines() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkbenchTaskStore(url: url)
        let first = TaskWorktreeLink(path: "/wt-a", baseCommit: "abc")
        let task = try await store.create(commonDirectory: "/common", title: "  Login  ", notes: "notes", agent: .kiro, links: [first])
        try await store.associate(id: task.id, link: TaskWorktreeLink(path: "/wt-a", baseCommit: "new-head"))
        try await store.associate(id: task.id, link: TaskWorktreeLink(path: "/wt-b", baseCommit: "def"))
        try await store.setStage(id: task.id, stage: .review)
        let restored = try await WorkbenchTaskStore(url: url).tasks(commonDirectory: "/common")
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].title, "Login")
        XCTAssertEqual(restored[0].agent, .kiro)
        XCTAssertEqual(restored[0].stage, .review)
        XCTAssertEqual(restored[0].worktrees.map(\.baseCommit), ["abc", "def"])
        let unrelated = try await store.tasks(commonDirectory: "/other")
        XCTAssertTrue(unrelated.isEmpty)
        try await store.delete(id: task.id)
        let remaining = try await store.tasks(commonDirectory: "/common")
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptOrFutureDataCannotBeOverwritten() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for contents in ["not json", "{\"version\":999,\"projects\":[],\"tasks\":[]}"] {
            try Data(contents.utf8).write(to: url)
            do {
                _ = try await WorkbenchTaskStore(url: url).create(commonDirectory: "/repo", title: "test", notes: "", agent: .codex,
                                                                links: [TaskWorktreeLink(path: "/repo", baseCommit: nil)])
                XCTFail("Invalid data must block writes")
            } catch { }
            XCTAssertEqual(try String(contentsOf: url), contents)
        }
    }

    func testFailedWriteDoesNotPublishTaskAndEmptyTaskIsRejected() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let blocker = url.deletingLastPathComponent()
        try Data("block directory creation".utf8).write(to: blocker)
        let store = WorkbenchTaskStore(url: url)
        do {
            _ = try await store.create(commonDirectory: "/repo", title: "test", notes: "", agent: .codex,
                                       links: [TaskWorktreeLink(path: "/repo", baseCommit: nil)])
            XCTFail("Write should fail")
        } catch { }
        try FileManager.default.removeItem(at: blocker)
        let tasks = try await store.tasks(commonDirectory: "/repo")
        XCTAssertTrue(tasks.isEmpty)
        do {
            _ = try await store.create(commonDirectory: "/repo", title: "  ", notes: "", agent: .codex, links: [])
            XCTFail("Empty task should fail")
        } catch { }
    }

    func testChangesIncludeCommittedStagedAndUnstagedEditsAgainstBaseline() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("code.txt", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let service = WorkbenchChangesService()
        let baseline = try await service.baseline(path: repo.path)
        try repo.writeFile("code.txt", contents: "committed\n")
        try repo.commitAll(message: "task change")
        try repo.writeFile("staged.txt", contents: "staged-content\n")
        try repo.run(["add", "staged.txt"])
        try repo.writeFile("code.txt", contents: "working-content\n")
        try repo.writeFile("untracked.txt", contents: "do-not-ingest-secret\n")
        let changes = try await service.changes(link: baseline)
        XCTAssertTrue(changes.patch.contains("-initial"))
        XCTAssertTrue(changes.patch.contains("+working-content"))
        XCTAssertTrue(changes.patch.contains("+staged-content"))
        XCTAssertTrue(changes.status.contains("untracked.txt"))
        XCTAssertFalse(changes.patch.contains("do-not-ingest-secret"))
        XCTAssertEqual(try repo.readFile("code.txt"), "working-content\n")
    }

    func testUnbornBranchAndMissingBaseline() async throws {
        let repo = try TemporaryGitRepository()
        let service = WorkbenchChangesService()
        let baseline = try await service.baseline(path: repo.path)
        XCTAssertNil(baseline.baseCommit)
        try repo.writeFile("staged.txt", contents: "new\n")
        try repo.run(["add", "staged.txt"])
        let changes = try await service.changes(link: baseline)
        XCTAssertTrue(changes.patch.contains("+new"))
        do {
            _ = try await service.changes(link: TaskWorktreeLink(path: repo.path, baseCommit: String(repeating: "a", count: 40)))
            XCTFail("Missing commit must not silently use HEAD")
        } catch { }
    }

    @MainActor
    func testDedicatedWorktreeTaskCreationAndDeletingTaskKeepsFiles() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let destination = repo.url.deletingLastPathComponent().appendingPathComponent("GitN-task-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = WorkbenchModel(path: repo.path, store: WorkbenchTaskStore(url: url))
        await model.refresh()
        let created = await model.createTask(title: "Dedicated task", notes: "", agent: .kiro,
                                             existingPath: nil, newPath: destination.path, branch: "task/dedicated")
        XCTAssertTrue(created)
        let task = try XCTUnwrap(model.selectedTask)
        XCTAssertEqual(task.worktrees.first?.baseCommit, try repo.headHash())
        XCTAssertEqual(model.worktrees.count, 2)
        await model.deleteTask(task)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("file").path))
        XCTAssertTrue(try repo.run(["show-ref", "--verify", "refs/heads/task/dedicated"]).contains("refs/heads/task/dedicated"))
    }

    @MainActor
    func testLinkedWorktreesShareTasksAndMissingDirectoryKeepsRecord() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("file", contents: "initial\n")
        try repo.commitAll(message: "initial")
        let linked = repo.url.deletingLastPathComponent().appendingPathComponent("GitN-linked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: linked) }
        try await WorktreeService(repoPath: repo.path).add(path: linked.path, branch: "linked", createBranch: true)
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkbenchTaskStore(url: url)
        let model = WorkbenchModel(path: linked.path, store: store)
        await model.refresh()
        let created = await model.createTask(title: "test", notes: "", agent: .codex,
                                             existingPath: linked.path, newPath: "", branch: "")
        XCTAssertTrue(created)
        let main = WorkbenchModel(path: repo.path, store: store)
        await main.refresh()
        XCTAssertEqual(main.tasks.count, 1)
        let worktree = try XCTUnwrap(main.worktrees.first { !$0.isMain })
        try await WorktreeService(repoPath: repo.path).remove(worktree)
        await main.refresh()
        XCTAssertEqual(main.tasks.count, 1)
        let task = try XCTUnwrap(main.tasks.first)
        XCTAssertEqual(task.worktrees[0].path, WorktreeService.canonicalPath(linked.path))
        XCTAssertNil(main.changes)
        XCTAssertNil(main.error, "A missing task directory must not block the Sessions page")
        main.showsTaskChanges = true
        await main.loadChanges()
        XCTAssertNotNil(main.changesError)
    }
}

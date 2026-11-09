import Foundation
import XCTest
@testable import GitN

final class ExternalSessionTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GitN-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func observation(_ id: String = "session-1", agent: WorkbenchAgent = .codex,
                             title: String? = nil, date: Date = Date(), receipt: String? = nil) -> SessionObservation {
        SessionObservation(agent: agent, namespace: "/source", externalID: id, title: title,
            cwd: "/repo", observedAt: date, event: "Stop", receiptID: receipt)
    }
    private func association(_ path: String = "/repo", date: Date = Date()) -> SessionWorktreeAssociation {
        SessionWorktreeAssociation(path: path, commonDirectory: "/common", source: .reportedDirectory,
            firstObservedAt: date, lastObservedAt: date)
    }

    func testIndependentProviderIDsAndMultipleSessionsShareWorktree() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkbenchTaskStore(url: root.appendingPathComponent("tasks.json"))
        let a = try await store.ingest(observation("same"), association: association())
        let b = try await store.ingest(observation("another"), association: association())
        let c = try await store.ingest(observation("same", agent: .kiro), association: association())
        var otherSource = observation("same"); otherSource = SessionObservation(agent: .codex, namespace: "/another-source",
            externalID: otherSource.externalID, observedAt: Date())
        let d = try await store.ingest(otherSource, association: association())
        XCTAssertEqual(Set([a,b,c,d]).count, 4)
        let resumed = try await store.ingest(observation("same", title: "Resumed"), association: association())
        XCTAssertEqual(a, resumed)
        let snapshot = try await store.sessionSnapshot(commonDirectory: "/common", includeUnassociated: false)
        XCTAssertEqual(snapshot.sessions.count, 4)
        XCTAssertTrue(snapshot.sessions.allSatisfy { $0.worktrees.count == 1 })
    }

    func testDelayedTitlesDuplicateEventsAndOlderEventsCannotRegressState() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkbenchTaskStore(url: root.appendingPathComponent("tasks.json"))
        let now = Date()
        let id = try await store.ingest(observation(date: now, receipt: "first"), association: nil)
        var snapshot = try await store.sessionSnapshot(commonDirectory: "/common", includeUnassociated: true)
        XCTAssertTrue(snapshot.sessions[0].displayTitle.contains("session-1"))
        _ = try await store.ingest(observation(title: "Latest title", date: now.addingTimeInterval(20)), association: association("/new"))
        _ = try await store.ingest(observation(title: "Old title", date: now.addingTimeInterval(-20)), association: association("/old"))
        _ = try await store.ingest(observation(date: now.addingTimeInterval(40)), association: nil)
        _ = try await store.ingest(observation(title: "Duplicate must not replace title", date: now.addingTimeInterval(60), receipt: "first"), association: nil)
        snapshot = try await store.sessionSnapshot(commonDirectory: "/common", includeUnassociated: false)
        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.externalTitle, "Latest title")
        XCTAssertEqual(session.lastObservedAt.timeIntervalSince1970, now.addingTimeInterval(40).timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(Set(session.worktrees.map(\.path)), ["/old", "/new"])
    }

    func testUnassociatedSessionCanCreateTaskAndGroupBothProvidersWithoutOverwritingTitle() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkbenchTaskStore(url: root.appendingPathComponent("tasks.json"))
        let a = try await store.ingest(observation(title: "Initial title"), association: nil)
        let b = try await store.ingest(observation("kiro-session", agent: .kiro), association: nil)
        let task = try await store.createTaskFromSession(id: a, commonDirectory: "/common", links: [])
        XCTAssertTrue(task.worktrees.isEmpty)
        try await store.groupSession(id: b, taskID: task.id, links: [TaskWorktreeLink(path: "/repo", baseCommit: "original")])
        try await store.groupSession(id: b, taskID: task.id, links: [TaskWorktreeLink(path: "/repo", baseCommit: "later")])
        _ = try await store.ingest(observation(title: "Renamed outside GitN"), association: nil)
        let tasks = try await store.tasks(commonDirectory: "/common")
        XCTAssertEqual(tasks[0].title, "Initial title")
        XCTAssertEqual(tasks[0].worktrees[0].baseCommit, "original")
        var snapshot = try await store.sessionSnapshot(commonDirectory: "/common", includeUnassociated: false)
        XCTAssertEqual(snapshot.sessions.count, 2)
        XCTAssertEqual(snapshot.memberships.count, 2)
        try await store.delete(id: task.id)
        snapshot = try await store.sessionSnapshot(commonDirectory: "/common", includeUnassociated: true)
        XCTAssertEqual(snapshot.sessions.count, 2)
        XCTAssertTrue(snapshot.memberships.isEmpty)
    }

    func testVersionOneTasksMigrateWithOriginalBackup() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tasks.json")
        let original = Data("{\"version\":1,\"projects\":[],\"tasks\":[]}".utf8)
        try original.write(to: url)
        _ = try await WorkbenchTaskStore(url: url).ingest(observation(), association: nil)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("v1-backup")), original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        let restored = try await WorkbenchTaskStore(url: url).sessionSnapshot(commonDirectory: "/common", includeUnassociated: true)
        XCTAssertEqual(restored.sessions.count, 1)
    }

    func testDirectoryResolverHandlesNestedSymlinksAndMissingDirectory() async throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("nested/file", contents: "hello")
        try repo.commitAll(message: "initial")
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repo.url)
        let resolver = SessionDirectoryResolver()
        let association = await resolver.resolve(alias.appendingPathComponent("nested").path, at: Date())
        XCTAssertEqual(association?.path, WorktreeService.canonicalPath(repo.path))
        let missing = await resolver.resolve(root.appendingPathComponent("missing").path, at: Date())
        XCTAssertNil(missing)
        let unknown = await resolver.resolve(nil, at: Date())
        XCTAssertNil(unknown)
    }

    func testCodexPageIgnoresPromptPreviewsAndHasOptionalTitle() throws {
        let observations = try CodexSessionDiscovery.parsePage(["data": [
            ["id": "a", "name": "Title", "cwd": "/repo", "updatedAt": 1234, "preview": "SECRET PROMPT"],
            ["id": "b", "updatedAt": 1235]
        ]], namespace: "/codex")
        XCTAssertEqual(observations.map(\.externalID), ["a", "b"])
        XCTAssertEqual(observations[0].title, "Title")
        XCTAssertNil(observations[1].title)
        XCTAssertNil(observations[1].cwd)
        XCTAssertThrowsError(try CodexSessionDiscovery.parsePage(["data": [["name": "no id"]]], namespace: "/codex"))
    }

    func testAppServerProtocolPagesAndNeverStartsOrResumesAThread() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-codex")
        let source = """
        #!/usr/bin/python3
        import sys,json
        for line in sys.stdin:
            request=json.loads(line)
            method=request['method']
            if method=='initialized':continue
            if method=='initialize':result={'userAgent':'fixture'}
            elif method=='thread/list':
                assert request['params']['limit']==50
                if request['params'].get('cursor')=='second':result={'data':[{'id':'b','updatedAt':2}],'nextCursor':None}
                else:result={'data':[{'id':'a','name':'A','cwd':'/repo','updatedAt':1}],'nextCursor':'second'}
            else:raise RuntimeError('Unexpected mutating request: '+method)
            print(json.dumps({'id':request['id'],'result':result}),flush=True)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let sessions = try await CodexSessionDiscovery(executable: script, namespace: "/fixture").discover()
        XCTAssertEqual(sessions.map(\.externalID), ["a", "b"])
    }

    func testHookSetupPreservesForeignHandlersAndOnlyRemovesOwnedEntries() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let relay = root.appendingPathComponent("relay")
        try Data("relay fixture".utf8).write(to: relay)
        let setup = SessionHookSetup(repoPath: root.appendingPathComponent("repo's directory").path,
            home: root, support: root.appendingPathComponent("support's folder"), bundledRelay: relay)
        let url = setup.configurationURL(.codex)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let foreign: [String: Any] = ["description": "keep", "hooks": ["SessionStart": [["hooks": [["type":"command", "command":"foreign-command"]]]]]]
        try JSONSerialization.data(withJSONObject: foreign).write(to: url)
        try setup.install(.codex)
        try setup.install(.codex)
        XCTAssertTrue(setup.isInstalled(.codex))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var hooks = try XCTUnwrap(json["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(hooks["SessionStart"]?.count, 2)
        XCTAssertEqual(json["description"] as? String, "keep")
        try setup.uninstall(.codex)
        XCTAssertFalse(setup.isInstalled(.codex))
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        hooks = try XCTUnwrap(json["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(hooks["SessionStart"]?.count, 1)
        XCTAssertTrue(setup.command(.codex).contains("'\\''"))
        try setup.install(.kiro)
        XCTAssertTrue(setup.isInstalled(.kiro))
        try setup.uninstall(.kiro)
        XCTAssertFalse(setup.isInstalled(.kiro))
    }

    func testMetadataProcessTimeoutAndCancellationStopWaiting() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("sleeping-server")
        try "#!/bin/sh\nexec /bin/sleep 10\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let start = Date()
        do {
            _ = try await CodexSessionDiscovery(executable: executable, namespace: "/fixture", timeout: 0.1).discover()
            XCTFail("Expected timeout")
        } catch { }
        let task = Task { try await CodexSessionDiscovery(executable: executable, namespace: "/fixture").discover() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testServerExitIsAnErrorInsteadOfSIGPIPE() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("exiting-server")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        do {
            _ = try await CodexSessionDiscovery(executable: executable, namespace: "/fixture").discover()
            XCTFail("Expected EOF or broken pipe error")
        } catch { }
    }

    func testMalformedHookConfigPreservedAndInboxQuarantinesInvalidEvents() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let setup = SessionHookSetup(repoPath: root.path, home: root, support: root.appendingPathComponent("support"), bundledRelay: root.appendingPathComponent("relay"))
        let config = setup.configurationURL(.kiro)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("invalid json".utf8)
        try invalid.write(to: config)
        XCTAssertThrowsError(try setup.install(.kiro))
        XCTAssertEqual(try Data(contentsOf: config), invalid)
        let inbox = SessionHookInbox(url: root.appendingPathComponent("inbox"))
        try FileManager.default.createDirectory(at: inbox.url, withIntermediateDirectories: true)
        try invalid.write(to: inbox.url.appendingPathComponent("bad.json"))
        let event = SessionHookEnvelope(version: 1, id: "receipt", agent: .kiro, namespace: "/kiro",
            sessionID: "a", cwd: nil, event: "SessionStart", timestamp: Date())
        try JSONEncoder().encode(event).write(to: inbox.url.appendingPathComponent("valid.json"))
        let pending = try inbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertNil(try pending[0].event.observation().cwd)
        try inbox.acknowledge(pending[0])
        XCTAssertTrue(try inbox.pending().isEmpty)
    }

    func testRelayMinimizesBothProvidersAndNeverRetainsPromptsOrToolArguments() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = package.appendingPathComponent(".build/debug/GitNSessionRelay")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        for agent in WorkbenchAgent.allCases {
            let process = Process()
            process.executableURL = executable
            process.arguments = [agent.rawValue, "/source", root.path]
            let input = Pipe(), output = Pipe()
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data("{\"session_id\":\"s\",\"cwd\":\"/repo\",\"hook_event_name\":\"Stop\",\"prompt\":\"SECRET\",\"tool_input\":{\"password\":\"SECRET\"}}".utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET"))
            let event = try JSONDecoder().decode(SessionHookEnvelope.self, from: data)
            XCTAssertEqual(event.sessionID, "s")
        }
    }

    func testInstalledCodexReadOnlyDiscoveryWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["GITN_TEST_CODEX_DISCOVERY"] == "1",
              let executable = CodexSessionDiscovery.installedExecutable() else { throw XCTSkip("Opt-in local runtime check") }
        let sessions = try await CodexSessionDiscovery(executable: executable, namespace: "/test-only").discover()
        XCTAssertTrue(sessions.allSatisfy { !$0.externalID.isEmpty })
    }
}

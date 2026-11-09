import Foundation

struct SessionHookSetup: Sendable {
    let repoPath: String
    let home: URL
    let support: URL
    let bundledRelay: URL?

    init(repoPath: String, home: URL = URL(fileURLWithPath: NSHomeDirectory()),
         support: URL = SessionHookInbox.defaultURL.deletingLastPathComponent(), bundledRelay: URL? = nil) {
        self.repoPath = repoPath
        self.home = home
        self.support = support
        let packaged = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/GitNSessionRelay")
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("GitNSessionRelay")
        self.bundledRelay = bundledRelay ?? [packaged, sibling].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var installedRelay: URL { support.appendingPathComponent("GitNSessionRelay") }
    func configurationURL(_ agent: WorkbenchAgent) -> URL {
        URL(fileURLWithPath: repoPath).appendingPathComponent(agent == .codex ? ".codex/hooks.json" : ".kiro/hooks/gitn-sessions.json")
    }
    func namespace(_ agent: WorkbenchAgent) -> String {
        if agent == .codex, let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return WorktreeService.canonicalPath(codexHome)
        }
        return WorktreeService.canonicalPath(home.appendingPathComponent(agent == .codex ? ".codex" : ".kiro").path)
    }
    func command(_ agent: WorkbenchAgent) -> String {
        [installedRelay.path, agent.rawValue, namespace(agent), support.appendingPathComponent("inbox").path]
            .map(Self.quote).joined(separator: " ") + " >/dev/null 2>&1 || true"
    }
    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func install(_ agent: WorkbenchAgent) throws {
        guard let bundledRelay else { throw GitError.operationFailed("Session relay is missing from this app build.") }
        let url = configurationURL(agent)
        let existing = try read(url)
        let updated = try configuration(existing, agent: agent, installing: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(contentsOf: bundledRelay).write(to: installedRelay, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedRelay.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("gitn-backup-" + UUID().uuidString)
            try FileManager.default.copyItem(at: url, to: backup)
        }
        try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    func uninstall(_ agent: WorkbenchAgent) throws {
        let url = configurationURL(agent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let updated = try configuration(try read(url), agent: agent, installing: false)
        // Keep an inert Kiro file so removal does not delete unrelated local data.
        try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    func isInstalled(_ agent: WorkbenchAgent) -> Bool {
        guard let document = try? read(configurationURL(agent)) else { return false }
        if agent == .kiro {
            return (document["hooks"] as? [[String: Any]])?.contains { isOwnedAction($0["action"] as? [String: Any], agent: agent) } == true
        }
        return (document["hooks"] as? [String: [[String: Any]]])?.values.contains { groups in
            groups.contains { group in (group["hooks"] as? [[String: Any]])?.contains { isOwnedAction($0, agent: agent) } == true }
        } == true
    }

    private func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw GitError.operationFailed("Invalid hook configuration; original file has been preserved.")
        }
        return document
    }

    private func isOwnedAction(_ action: [String: Any]?, agent: WorkbenchAgent) -> Bool {
        action?["command"] as? String == command(agent)
    }

    private func configuration(_ original: [String: Any], agent: WorkbenchAgent, installing: Bool) throws -> [String: Any] {
        var result = original
        let events = ["SessionStart", "PostToolUse", "Stop"]
        if agent == .kiro {
            guard original.isEmpty || (original["version"] as? String == "v1" && original["hooks"] is [[String: Any]]) else {
                throw GitError.operationFailed("Existing Kiro hooks use an unsupported format; file preserved.")
            }
            var hooks = (original["hooks"] as? [[String: Any]] ?? []).filter { !isOwnedAction($0["action"] as? [String: Any], agent: agent) }
            if installing {
                hooks += events.map { ["name": "GitN " + $0, "trigger": $0,
                    "action": ["type": "command", "command": command(agent)], "timeout": 5] }
            }
            result["version"] = "v1"
            result["hooks"] = hooks
        } else {
            if let hooks = original["hooks"], !(hooks is [String: [[String: Any]]]) {
                throw GitError.operationFailed("Unsupported Codex hook configuration; original preserved.")
            }
            var hooks = original["hooks"] as? [String: [[String: Any]]] ?? [:]
            for event in Array(hooks.keys) {
                hooks[event] = hooks[event]?.compactMap { group in
                    guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                    let kept = handlers.filter { !isOwnedAction($0, agent: agent) }
                    if !handlers.isEmpty && kept.isEmpty { return nil }
                    var group = group; group["hooks"] = kept; return group
                }
            }
            if installing {
                for event in events {
                    hooks[event, default: []].append(["hooks": [["type": "command", "command": command(agent), "timeout": 5]]])
                }
            }
            result["hooks"] = hooks
        }
        return result
    }
}

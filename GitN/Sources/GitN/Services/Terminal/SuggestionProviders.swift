import Foundation

/// Read-only providers for dynamic suggestion data, scoped to a cwd. All git
/// access is read-only argv calls (never a shell string); results use reliable
/// delimiters, not fragile line/space parsing (SPEC §7.1).
enum SuggestionProviders {
    /// Directories (and a trailing-slash hint) under `cwd` matching `prefix`.
    /// Handles an absolute or `~`-relative prefix and a trailing path segment.
    static func directories(cwd: String, prefix: String) -> [CommandSuggestion] {
        let fm = FileManager.default
        let (searchDir, partial, displayBase) = resolveSearchDir(cwd: cwd, prefix: prefix)

        guard let entries = try? fm.contentsOfDirectory(atPath: searchDir) else { return [] }
        var results: [CommandSuggestion] = []
        for name in entries.sorted() {
            if name.hasPrefix(".") && !partial.hasPrefix(".") { continue }
            guard partial.isEmpty || name.hasPrefix(partial) else { continue }
            var isDir: ObjCBool = false
            let full = (searchDir as NSString).appendingPathComponent(name)
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            let insert = ShellWordEscaping.escape(displayBase + name) + "/"
            results.append(CommandSuggestion(
                id: "dir:\(full)",
                displayName: name + "/",
                insertText: insert,
                detail: nil,
                kind: .path
            ))
        }
        return results
    }

    private static func resolveSearchDir(cwd: String, prefix: String) -> (dir: String, partial: String, displayBase: String) {
        var base = prefix
        var displayBase = ""
        // Expand a leading ~ for searching, but keep it for display/insertion.
        if base == "~" || base.hasPrefix("~/") {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            base = home + String(base.dropFirst(1))
        }
        let nsBase = base as NSString
        if base.hasSuffix("/") {
            displayBase = prefix
            let dir = base.hasPrefix("/") ? base : (cwd as NSString).appendingPathComponent(base)
            return (dir, "", displayBase)
        }
        let partial = nsBase.lastPathComponent
        let parent = nsBase.deletingLastPathComponent
        if !parent.isEmpty {
            displayBase = String(prefix.dropLast(partial.count))
            let dir = parent.hasPrefix("/") ? parent : (cwd as NSString).appendingPathComponent(parent)
            return (dir, partial, displayBase)
        }
        return (cwd, partial, "")
    }

    /// Local branch names via `git branch --format=%(refname:short)` (read-only).
    static func gitBranches(cwd: String, prefix: String) async -> [CommandSuggestion] {
        let output = await runGit(["branch", "--format=%(refname:short)"], cwd: cwd)
        let names = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return names
            .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
            .map {
                CommandSuggestion(
                    id: "branch:\($0)",
                    displayName: $0,
                    insertText: ShellWordEscaping.escape($0),
                    detail: nil,
                    kind: .branch
                )
            }
    }

    /// Changed working-tree files via `git status --porcelain -z` (NUL-delimited
    /// so paths with spaces/newlines are safe — never line/space parsing).
    static func gitFiles(cwd: String, prefix: String) async -> [CommandSuggestion] {
        let output = await runGit(["status", "--porcelain", "-z"], cwd: cwd)
        // -z records are NUL-separated; each is "XY <path>".
        let records = output.split(separator: "\u{0}", omittingEmptySubsequences: true)
        var results: [CommandSuggestion] = []
        for record in records {
            let text = String(record)
            guard text.count > 3 else { continue }
            let path = String(text.dropFirst(3))
            guard prefix.isEmpty || path.hasPrefix(prefix) else { continue }
            results.append(CommandSuggestion(
                id: "file:\(path)",
                displayName: path,
                insertText: ShellWordEscaping.escape(path),
                detail: nil,
                kind: .file
            ))
        }
        return results
    }

    /// Scripts from the nearest package.json at or above `cwd`.
    static func packageScripts(cwd: String, prefix: String) -> [CommandSuggestion] {
        guard let packageURL = nearestPackageJSON(from: cwd),
              let data = try? Data(contentsOf: packageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any] else {
            return []
        }
        return scripts.keys.sorted()
            .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
            .map {
                CommandSuggestion(
                    id: "script:\($0)",
                    displayName: $0,
                    insertText: ShellWordEscaping.escape($0),
                    detail: (scripts[$0] as? String),
                    kind: .script
                )
            }
    }

    private static func nearestPackageJSON(from cwd: String) -> URL? {
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<40 {
            let candidate = dir.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Run a read-only git command, returning stdout as a string (empty on error).
    private static func runGit(_ args: [String], cwd: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

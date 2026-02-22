import Foundation

enum CompletionResult {
    case none
    case single(completed: String)
    case multiple(completed: String, candidates: [String])
}

struct TabCompletionEngine {
    let workingDirectory: String

    func complete(input: String) -> CompletionResult {
        guard !input.isEmpty else { return .none }

        let tokens = tokenize(input)
        let trailingSpace = input.last == " "

        if tokens.isEmpty || (tokens.count == 1 && !trailingSpace) {
            let prefix = tokens.first ?? ""
            if prefix.contains("/") {
                return completeFilePath(tokens: tokens, prefix: prefix, fullInput: input)
            }
            return completeCommand(prefix: prefix, fullInput: input)
        }

        let prefix = trailingSpace ? "" : (tokens.last ?? "")
        return completeFilePath(tokens: tokens, prefix: prefix, fullInput: input)
    }

    // MARK: - Command completion (first token, searched in PATH)

    private func completeCommand(prefix: String, fullInput: String) -> CompletionResult {
        guard !prefix.isEmpty else { return .none }

        var seen = Set<String>()
        var matches = [String]()

        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)

        let fm = FileManager.default
        for dir in pathDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasPrefix(prefix) && !seen.contains(entry) {
                let full = (dir as NSString).appendingPathComponent(entry)
                if fm.isExecutableFile(atPath: full) {
                    seen.insert(entry)
                    matches.append(entry)
                }
            }
        }

        // Also check shell builtins
        let builtins = [
            "cd", "echo", "export", "alias", "unalias", "source", "eval", "exec",
            "exit", "set", "unset", "pushd", "popd", "dirs", "history", "jobs",
            "fg", "bg", "wait", "kill", "type", "which", "pwd", "true", "false",
        ]
        for b in builtins where b.hasPrefix(prefix) && !seen.contains(b) {
            seen.insert(b)
            matches.append(b)
        }

        matches.sort()
        return buildResult(matches: matches, prefix: prefix, fullInput: fullInput, appendSlash: false)
    }

    // MARK: - File / directory completion

    private func completeFilePath(tokens: [String], prefix: String, fullInput: String) -> CompletionResult {
        let expanded = expandTilde(prefix)
        let (searchDir, partial) = splitPathPrefix(expanded)
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: searchDir) else { return .none }

        let matches: [String]
        if partial.isEmpty {
            matches = entries.filter { !$0.hasPrefix(".") }.sorted()
        } else {
            matches = entries.filter { $0.hasPrefix(partial) }.sorted()
        }

        guard !matches.isEmpty else { return .none }

        let completedNames = matches.map { name -> String in
            let fullPath = (searchDir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            return isDir.boolValue ? name + "/" : name
        }

        let displayNames = completedNames.map { name -> String in
            name.hasSuffix("/") ? String(name.dropLast()) + "/" : name
        }

        let inputBeforeToken: String
        if fullInput.last == " " || prefix.isEmpty {
            inputBeforeToken = fullInput
        } else {
            let idx = fullInput.index(fullInput.endIndex, offsetBy: -prefix.count)
            inputBeforeToken = String(fullInput[..<idx])
        }

        let pathPrefix: String
        let range = expanded.range(of: partial, options: .backwards)
        if let range {
            pathPrefix = String(prefix[prefix.startIndex..<prefix.index(prefix.startIndex, offsetBy: expanded.distance(from: expanded.startIndex, to: range.lowerBound))])
        } else {
            pathPrefix = ""
        }

        if completedNames.count == 1 {
            let completed = inputBeforeToken + pathPrefix + completedNames[0]
            return .single(completed: completed)
        }

        let common = longestCommonPrefix(completedNames)
        let completed = inputBeforeToken + pathPrefix + common
        return .multiple(completed: completed, candidates: displayNames)
    }

    // MARK: - Helpers

    private func tokenize(_ input: String) -> [String] {
        var tokens = [String]()
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for ch in input {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && !inSingleQuote {
                escaped = true
                continue
            }
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if ch == " " && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return (NSString(string: path).expandingTildeInPath)
        }
        if path == "~" {
            return NSHomeDirectory()
        }
        return path
    }

    private func splitPathPrefix(_ path: String) -> (directory: String, partial: String) {
        if path.isEmpty {
            return (workingDirectory, "")
        }
        let nsPath = path as NSString
        let lastComponent = nsPath.lastPathComponent
        let dirPart = nsPath.deletingLastPathComponent

        if path.hasSuffix("/") {
            let dir = path.hasPrefix("/") ? path : (workingDirectory as NSString).appendingPathComponent(path)
            return (dir, "")
        }

        let directory: String
        if dirPart.isEmpty || dirPart == "." {
            directory = workingDirectory
        } else if dirPart.hasPrefix("/") {
            directory = dirPart
        } else {
            directory = (workingDirectory as NSString).appendingPathComponent(dirPart)
        }
        return (directory, lastComponent)
    }

    private func longestCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var prefix = first
        for s in strings.dropFirst() {
            while !s.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }
        return prefix
    }

    private func buildResult(matches: [String], prefix: String, fullInput: String, appendSlash: Bool) -> CompletionResult {
        guard !matches.isEmpty else { return .none }

        let inputBeforeToken: String
        if prefix.isEmpty {
            inputBeforeToken = fullInput
        } else {
            let idx = fullInput.index(fullInput.endIndex, offsetBy: -prefix.count)
            inputBeforeToken = String(fullInput[..<idx])
        }

        if matches.count == 1 {
            let completed = inputBeforeToken + matches[0] + " "
            return .single(completed: completed)
        }

        let common = longestCommonPrefix(matches)
        let completed = inputBeforeToken + common
        if completed == fullInput {
            return .multiple(completed: fullInput, candidates: matches)
        }
        return .multiple(completed: completed, candidates: matches)
    }
}

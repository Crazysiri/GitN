import Foundation

struct GitLFSSupport: Sendable {
    struct PointerInfo: Sendable {
        let oid: String
        let size: Int
    }

    struct ResolvedData: Sendable {
        let data: Data?
        let isLFSPointer: Bool
        let wasResolved: Bool
    }

    private let repoPath: String
    private let cli: GitCLI

    init(repoPath: String) {
        self.repoPath = repoPath
        self.cli = GitCLI(repoPath: repoPath)
    }

    func repositoryUsesLFS(fileManager: FileManager = .default) -> Bool {
        Self.repositoryUsesLFS(at: URL(fileURLWithPath: repoPath, isDirectory: true), fileManager: fileManager)
    }

    func pull(remoteName: String? = nil, branchName: String? = nil) async throws {
        guard repositoryUsesLFS() else { return }

        try await ensureLFSAvailable()

        var args = ["lfs", "pull"]
        if let remoteName {
            args.append(remoteName)
            if let branchName {
                args.append(branchName)
            }
        }
        try await cli.run(args)
    }

    func push(remoteName: String? = nil, branchName: String? = nil) async throws {
        guard repositoryUsesLFS() else { return }

        try await ensureLFSAvailable()

        let effectiveRemote = remoteName ?? "origin"
        let effectiveRef = branchName ?? "HEAD"
        try await cli.run(["lfs", "push", effectiveRemote, effectiveRef])
    }

    func resolveDataIfNeeded(_ data: Data, path: String) -> ResolvedData {
        guard let pointer = Self.pointerInfo(for: data) else {
            return ResolvedData(data: data, isLFSPointer: false, wasResolved: false)
        }

        if let localObject = localObjectData(for: pointer) {
            return ResolvedData(data: localObject, isLFSPointer: true, wasResolved: true)
        }

        guard let resolved = try? smudge(pointerData: data, path: path) else {
            return ResolvedData(data: nil, isLFSPointer: true, wasResolved: false)
        }

        return ResolvedData(data: resolved, isLFSPointer: true, wasResolved: true)
    }

    private func ensureLFSAvailable() async throws {
        do {
            _ = try await cli.output(["lfs", "version"])
        } catch {
            throw GitError.operationFailed(
                "Repository uses Git LFS, but `git lfs` is unavailable. Install Git LFS, run `git lfs install`, and retry."
            )
        }
    }

    static func repositoryUsesLFS(at repoURL: URL, fileManager: FileManager = .default) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }

            guard fileURL.lastPathComponent == ".gitattributes" else { continue }
            guard Self.fileDeclaresLFS(fileURL) else { continue }
            return true
        }

        return false
    }

    static func isLFSPointerData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else { return false }

        let versionLine = lines[0].trimmingCharacters(in: .whitespaces)
        let oidLine = lines[1].trimmingCharacters(in: .whitespaces)
        let sizeLine = lines[2].trimmingCharacters(in: .whitespaces)

        return versionLine == "version https://git-lfs.github.com/spec/v1"
            && oidLine.hasPrefix("oid sha256:")
            && sizeLine.hasPrefix("size ")
    }

    static func pointerInfo(for data: Data) -> PointerInfo? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else { return nil }

        let versionLine = lines[0].trimmingCharacters(in: .whitespaces)
        let oidLine = lines[1].trimmingCharacters(in: .whitespaces)
        let sizeLine = lines[2].trimmingCharacters(in: .whitespaces)

        guard versionLine == "version https://git-lfs.github.com/spec/v1",
              oidLine.hasPrefix("oid sha256:"),
              sizeLine.hasPrefix("size "),
              let size = Int(sizeLine.dropFirst("size ".count))
        else {
            return nil
        }

        let oid = String(oidLine.dropFirst("oid sha256:".count))
        guard oid.count == 64 else { return nil }

        return PointerInfo(oid: oid, size: size)
    }

    private static func fileDeclaresLFS(_ fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let contents = String(decoding: data, as: UTF8.self)

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if line.contains("filter=lfs") {
                return true
            }
        }

        return false
    }

    private func localObjectData(for pointer: PointerInfo) -> Data? {
        guard let objectsRoot = lfsObjectsRoot() else { return nil }

        let first = String(pointer.oid.prefix(2))
        let second = String(pointer.oid.dropFirst(2).prefix(2))
        let objectURL = objectsRoot
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)
            .appendingPathComponent(pointer.oid, isDirectory: false)

        guard let data = try? Data(contentsOf: objectURL, options: [.mappedIfSafe]) else {
            return nil
        }

        if pointer.size > 0, data.count != pointer.size {
            return nil
        }

        return data
    }

    private func lfsObjectsRoot(fileManager: FileManager = .default) -> URL? {
        guard let gitCommonDirectory = gitCommonDirectory(fileManager: fileManager) else { return nil }
        let objectsRoot = gitCommonDirectory
            .appendingPathComponent("lfs", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: objectsRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return objectsRoot
    }

    private func gitCommonDirectory(fileManager: FileManager = .default) -> URL? {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        let dotGitURL = repoURL.appendingPathComponent(".git", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return dotGitURL
        }

        guard let dotGitContents = try? String(contentsOf: dotGitURL, encoding: .utf8),
              let gitDirURL = Self.parseGitDir(from: dotGitContents, repoURL: repoURL)
        else {
            return nil
        }

        let commonDirURL = Self.resolveCommonDir(from: gitDirURL, fileManager: fileManager) ?? gitDirURL
        return commonDirURL
    }

    private static func parseGitDir(from contents: String, repoURL: URL) -> URL? {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }
        let rawPath = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else { return nil }
        return URL(fileURLWithPath: rawPath, relativeTo: repoURL).standardizedFileURL
    }

    private static func resolveCommonDir(from gitDirURL: URL, fileManager: FileManager = .default) -> URL? {
        let commonDirURL = gitDirURL.appendingPathComponent("commondir", isDirectory: false)
        guard fileManager.fileExists(atPath: commonDirURL.path),
              let contents = try? String(contentsOf: commonDirURL, encoding: .utf8)
        else {
            return nil
        }

        let rawPath = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }
        return URL(fileURLWithPath: rawPath, relativeTo: gitDirURL).standardizedFileURL
    }

    private func smudge(pointerData: Data, path: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["lfs", "smudge", "--", path]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        process.environment = GitCLI.enrichedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try process.run()
        stdinPipe.fileHandleForWriting.write(pointerData)
        stdinPipe.fileHandleForWriting.closeFile()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.isEmpty ? stdout : stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "git lfs smudge failed"
            throw GitError.operationFailed(message)
        }

        return stdout
    }
}

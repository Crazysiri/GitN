import Foundation

indirect enum WorkingTreeFileNode: Identifiable, Equatable, Sendable {
    case folder(name: String, relativePath: String)
    case file(name: String, relativePath: String)

    var id: String {
        switch self {
        case .folder(_, let relativePath):
            return "folder:\(relativePath)"
        case .file(_, let relativePath):
            return "file:\(relativePath)"
        }
    }

    var relativePath: String {
        switch self {
        case .folder(_, let relativePath):
            return relativePath
        case .file(_, let relativePath):
            return relativePath
        }
    }
}

struct WorkingTreeFileTreeBuilder {
    struct TreeSnapshot: Equatable, Sendable {
        let rootNodes: [WorkingTreeFileNode]
        let folderContents: [String: [WorkingTreeFileNode]]
        let expandedFolderPaths: Set<String>
        let matchedFilePaths: Set<String>

        static let empty = TreeSnapshot(rootNodes: [], folderContents: [:], expandedFolderPaths: [], matchedFilePaths: [])
    }

    private struct DirectoryEntry {
        let name: String
        let isDirectory: Bool
    }

    private let fileManager: FileManager
    private let excludedDirectoryNames: Set<String>

    init(
        fileManager: FileManager = .default,
        excludedDirectoryNames: Set<String> = [".git"]
    ) {
        self.fileManager = fileManager
        self.excludedDirectoryNames = excludedDirectoryNames
    }

    func build(at repositoryPath: String) throws -> [WorkingTreeFileNode] {
        try listDirectory(at: repositoryPath, relativePath: "")
    }

    func search(at repositoryPath: String, query: String) throws -> TreeSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .empty
        }

        let filePaths = try searchableFilePaths(at: repositoryPath)
        return search(in: filePaths, query: trimmedQuery)
    }

    func searchSnapshots(at repositoryPath: String, query: String) throws -> [TreeSnapshot] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [.empty] }

        let searchRoots = try listDirectory(at: repositoryPath, relativePath: "")
        let allSearchablePaths = try searchableFilePaths(at: repositoryPath)
        var matchingPaths: Set<String> = []
        var snapshots: [TreeSnapshot] = []

        for root in searchRoots {
            let beforeCount = matchingPaths.count
            for path in allSearchablePaths where pathIsWithinRoot(path, root: root.relativePath) && searchPath(path, matches: trimmedQuery) {
                matchingPaths.insert(path)
            }

            if matchingPaths.count != beforeCount {
                snapshots.append(treeSnapshot(matchingFilePaths: matchingPaths))
            }
        }

        return snapshots.isEmpty ? [.empty] : snapshots
    }

    func searchIncrementally(
        at repositoryPath: String,
        query: String,
        candidateFilePaths: Set<String>? = nil,
        snapshotPublishDelayNanoseconds: UInt64 = 0,
        onSnapshot: @Sendable (TreeSnapshot) async -> Void
    ) async throws {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            await onSnapshot(.empty)
            return
        }

        if let candidateFilePaths {
            let matches = Set(candidateFilePaths.filter { searchPath($0, matches: trimmedQuery) })
            await onSnapshot(treeSnapshot(matchingFilePaths: matches))
            return
        }

        let searchRoots = try listDirectory(at: repositoryPath, relativePath: "")
        let allSearchablePaths = try searchableFilePaths(at: repositoryPath)
        var matchingPaths: Set<String> = []
        var didPublishSnapshot = false

        for root in searchRoots {
            try Task.checkCancellation()
            let beforeCount = matchingPaths.count
            for path in allSearchablePaths where pathIsWithinRoot(path, root: root.relativePath) && searchPath(path, matches: trimmedQuery) {
                matchingPaths.insert(path)
            }

            if matchingPaths.count != beforeCount {
                didPublishSnapshot = true
                await onSnapshot(treeSnapshot(matchingFilePaths: matchingPaths))
                if snapshotPublishDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: snapshotPublishDelayNanoseconds)
                }
                await Task.yield()
            }
        }

        if !didPublishSnapshot {
            await onSnapshot(.empty)
        }
    }

    func search(in filePaths: [String], query: String) -> TreeSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return .empty }

        let matches = Set(filePaths.filter { searchPath($0, matches: trimmedQuery) })
        return treeSnapshot(matchingFilePaths: matches)
    }

    func treeSnapshot(matchingFilePaths filePaths: Set<String>) -> TreeSnapshot {
        guard !filePaths.isEmpty else { return .empty }
        return snapshot(from: filePaths)
    }

    func listDirectory(at repositoryPath: String, relativePath: String) throws -> [WorkingTreeFileNode] {
        let directoryURL = relativePath.isEmpty
            ? URL(fileURLWithPath: repositoryPath, isDirectory: true)
            : URL(fileURLWithPath: repositoryPath, isDirectory: true).appendingPathComponent(relativePath, isDirectory: true)
        return try listDirectory(at: directoryURL, relativePath: relativePath)
    }

    private func listDirectory(at directoryURL: URL, relativePath: String) throws -> [WorkingTreeFileNode] {
        try directoryEntries(at: directoryURL).map { entry in
            let name = entry.name
            let nodeRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"

            if entry.isDirectory {
                return .folder(name: name, relativePath: nodeRelativePath)
            }

            return .file(name: name, relativePath: nodeRelativePath)
        }
    }

    private func directoryEntries(at directoryURL: URL) throws -> [DirectoryEntry] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants]
        )

        let entries = try urls.compactMap { url -> DirectoryEntry? in
            let values = try url.resourceValues(forKeys: resourceKeys)
            let name = url.lastPathComponent
            let isDirectory = (values.isDirectory ?? false) && !(values.isSymbolicLink ?? false)

            if isDirectory && excludedDirectoryNames.contains(name) {
                return nil
            }

            return DirectoryEntry(name: name, isDirectory: isDirectory)
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func searchableFilePaths(at repositoryPath: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryPath, "ls-files", "-co", "--exclude-standard", "-z"]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "git ls-files failed"
            throw NSError(
                domain: "WorkingTreeFileTreeBuilder",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        guard !data.isEmpty else { return [] }

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func searchPath(_ path: String, matches query: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func pathIsWithinRoot(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func snapshot(from filePaths: Set<String>) -> TreeSnapshot {
        var childPathsByFolder: [String: Set<String>] = [:]
        var folderPaths: Set<String> = []
        var filePathsByFolder: [String: Set<String>] = [:]

        for filePath in filePaths {
            let parts = filePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let fileName = parts.last else { continue }
            let folderParts = parts.dropLast()
            let parentPath = folderParts.joined(separator: "/")
            filePathsByFolder[parentPath, default: []].insert(filePath)

            var currentFolder = ""
            for folderName in folderParts {
                let childPath = currentFolder.isEmpty ? folderName : "\(currentFolder)/\(folderName)"
                folderPaths.insert(childPath)
                childPathsByFolder[currentFolder, default: []].insert(childPath)
                currentFolder = childPath
            }

            if parentPath.isEmpty {
                childPathsByFolder["", default: []].insert(fileName)
            }
        }

        let allFolderPaths = folderPaths
        var folderContents: [String: [WorkingTreeFileNode]] = [:]
        let folderKeys = allFolderPaths.union([""])

        for folderPath in folderKeys {
            let folderNodes = (childPathsByFolder[folderPath] ?? [])
                .filter { allFolderPaths.contains($0) }
                .map { path in
                    WorkingTreeFileNode.folder(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path)
                }
            let fileNodes = (filePathsByFolder[folderPath] ?? [])
                .map { path in
                    WorkingTreeFileNode.file(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path)
                }
            let nodes = sortedNodes(folders: folderNodes, files: fileNodes)

            if folderPath.isEmpty {
                continue
            }
            folderContents[folderPath] = nodes
        }

        let rootNodes = sortedNodes(
            folders: (childPathsByFolder[""] ?? [])
                .filter { allFolderPaths.contains($0) }
                .map { path in
                    WorkingTreeFileNode.folder(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path)
                },
            files: (filePathsByFolder[""] ?? [])
                .map { path in
                    WorkingTreeFileNode.file(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path)
                }
        )

        return TreeSnapshot(
            rootNodes: rootNodes,
            folderContents: folderContents,
            expandedFolderPaths: allFolderPaths,
            matchedFilePaths: filePaths
        )
    }

    private func sortedNodes(
        folders: [WorkingTreeFileNode],
        files: [WorkingTreeFileNode]
    ) -> [WorkingTreeFileNode] {
        folders.sorted(by: compareNodesByName) + files.sorted(by: compareNodesByName)
    }

    private func compareNodesByName(_ lhs: WorkingTreeFileNode, _ rhs: WorkingTreeFileNode) -> Bool {
        lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

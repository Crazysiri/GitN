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

    func listDirectory(at repositoryPath: String, relativePath: String) throws -> [WorkingTreeFileNode] {
        let directoryURL = relativePath.isEmpty
            ? URL(fileURLWithPath: repositoryPath, isDirectory: true)
            : URL(fileURLWithPath: repositoryPath, isDirectory: true).appendingPathComponent(relativePath, isDirectory: true)
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

        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return sortedEntries.map { entry in
            let name = entry.name
            let nodeRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"

            if entry.isDirectory {
                return .folder(name: name, relativePath: nodeRelativePath)
            }

            return .file(name: name, relativePath: nodeRelativePath)
        }
    }
}

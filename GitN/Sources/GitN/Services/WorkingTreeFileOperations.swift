import Foundation

struct WorkingTreeFileOperations {
    enum OperationError: LocalizedError, Equatable {
        case emptyName
        case invalidName
        case itemAlreadyExists(String)
        case rootRenameUnsupported

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Name can't be empty."
            case .invalidName:
                return "Names can't contain path separators."
            case .itemAlreadyExists(let path):
                return "'\(path)' already exists."
            case .rootRenameUnsupported:
                return "The FILES root can't be renamed."
            }
        }
    }

    let repoPath: String
    private let fileManager: FileManager

    init(repoPath: String, fileManager: FileManager = .default) {
        self.repoPath = repoPath
        self.fileManager = fileManager
    }

    func absolutePath(for relativePath: String) -> String {
        guard !relativePath.isEmpty else { return repoPath }
        return (repoPath as NSString).appendingPathComponent(relativePath)
    }

    func createFile(named rawName: String, in parentRelativePath: String = "") throws -> String {
        let name = try Self.validatedInlineName(rawName)
        let relativePath = joinedPath(parentRelativePath, name)
        let fullPath = absolutePath(for: relativePath)
        guard !fileManager.fileExists(atPath: fullPath) else {
            throw OperationError.itemAlreadyExists(relativePath)
        }

        let directory = (fullPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        guard fileManager.createFile(atPath: fullPath, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return relativePath
    }

    func createFolder(named rawName: String, in parentRelativePath: String = "") throws -> String {
        let name = try Self.validatedInlineName(rawName)
        let relativePath = joinedPath(parentRelativePath, name)
        let fullPath = absolutePath(for: relativePath)
        guard !fileManager.fileExists(atPath: fullPath) else {
            throw OperationError.itemAlreadyExists(relativePath)
        }
        try fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: true, attributes: nil)
        return relativePath
    }

    func renameItem(at relativePath: String, to rawName: String) throws -> String {
        guard !relativePath.isEmpty else {
            throw OperationError.rootRenameUnsupported
        }

        let name = try Self.validatedInlineName(rawName)
        let sourcePath = absolutePath(for: relativePath)
        let parentRelativePath = (relativePath as NSString).deletingLastPathComponent
        let targetRelativePath = joinedPath(parentRelativePath == "/" ? "" : parentRelativePath, name)
        guard targetRelativePath != relativePath else {
            return relativePath
        }

        let targetPath = absolutePath(for: targetRelativePath)
        guard !fileManager.fileExists(atPath: targetPath) else {
            throw OperationError.itemAlreadyExists(targetRelativePath)
        }

        try fileManager.moveItem(atPath: sourcePath, toPath: targetPath)
        return targetRelativePath
    }

    func deleteItem(at relativePath: String) throws {
        let fullPath = absolutePath(for: relativePath)
        guard fileManager.fileExists(atPath: fullPath) else { return }
        try fileManager.removeItem(atPath: fullPath)
    }

    func itemExists(at relativePath: String) -> Bool {
        fileManager.fileExists(atPath: absolutePath(for: relativePath))
    }

    func isDirectory(at relativePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: absolutePath(for: relativePath), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func joinedPath(_ parentRelativePath: String, _ name: String) -> String {
        guard !parentRelativePath.isEmpty else { return name }
        return (parentRelativePath as NSString).appendingPathComponent(name)
    }

    static func validatedInlineName(_ rawName: String) throws -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OperationError.emptyName
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
            throw OperationError.invalidName
        }
        return trimmed
    }
}

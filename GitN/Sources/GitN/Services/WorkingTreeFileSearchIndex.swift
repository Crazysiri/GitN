import Foundation

actor WorkingTreeFileSearchIndex {
    struct IndexedFilePath: Equatable, Sendable {
        let relativePath: String
        let fileName: String
        let normalizedFileName: String
    }

    typealias Loader = @Sendable (String) async throws -> [String]

    nonisolated static let shared = WorkingTreeFileSearchIndex()
    private nonisolated static let liveLoader: Loader = { repositoryPath in
        let output = try await GitCLI(repoPath: repositoryPath).output([
            "ls-files", "-co", "--exclude-standard", "-z"
        ])

        guard !output.isEmpty else { return [] }

        return output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private struct InFlightLoad {
        let id: UUID
        let task: Task<[IndexedFilePath], Error>
    }

    private var cache: [String: [IndexedFilePath]] = [:]
    private var inFlightLoads: [String: InFlightLoad] = [:]
    private let loader: Loader

    init() {
        self.loader = WorkingTreeFileSearchIndex.liveLoader
    }

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func prewarm(repositoryPath: String) async {
        let path = normalizedRepositoryPath(repositoryPath)
        _ = try? await indexedFilePaths(for: path)
    }

    func invalidate(repositoryPath: String) {
        let path = normalizedRepositoryPath(repositoryPath)
        cache.removeValue(forKey: path)
        inFlightLoads.removeValue(forKey: path)?.task.cancel()
    }

    func search(
        repositoryPath: String,
        query: String,
        candidateFilePaths: Set<String>? = nil
    ) async throws -> WorkingTreeFileTreeBuilder.TreeSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return .empty }

        let normalizedQuery = Self.normalizedSearchKey(trimmedQuery)
        let builder = WorkingTreeFileTreeBuilder()

        if let candidateFilePaths {
            let matches = Set(
                candidateFilePaths.filter {
                    Self.normalizedSearchKey(URL(fileURLWithPath: $0).lastPathComponent).contains(normalizedQuery)
                }
            )
            return builder.treeSnapshot(matchingFilePaths: matches)
        }

        let indexedFilePaths = try await indexedFilePaths(for: normalizedRepositoryPath(repositoryPath))
        let matches = Set(
            indexedFilePaths.compactMap { indexedPath in
                indexedPath.normalizedFileName.contains(normalizedQuery) ? indexedPath.relativePath : nil
            }
        )
        return builder.treeSnapshot(matchingFilePaths: matches)
    }

    private func indexedFilePaths(for repositoryPath: String) async throws -> [IndexedFilePath] {
        if let cached = cache[repositoryPath] {
            return cached
        }

        if let inFlight = inFlightLoads[repositoryPath] {
            return try await inFlight.task.value
        }

        let loadID = UUID()
        let task = Task<[IndexedFilePath], Error> {
            let paths = try await loader(repositoryPath)
            return paths.map(Self.makeIndexedPath(from:))
        }
        inFlightLoads[repositoryPath] = InFlightLoad(id: loadID, task: task)

        do {
            let indexed = try await task.value
            if inFlightLoads[repositoryPath]?.id == loadID {
                cache[repositoryPath] = indexed
                inFlightLoads[repositoryPath] = nil
            }
            return indexed
        } catch {
            if inFlightLoads[repositoryPath]?.id == loadID {
                inFlightLoads[repositoryPath] = nil
            }
            throw error
        }
    }

    private func normalizedRepositoryPath(_ repositoryPath: String) -> String {
        (repositoryPath as NSString).standardizingPath
    }

    private static func makeIndexedPath(from path: String) -> IndexedFilePath {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return IndexedFilePath(
            relativePath: path,
            fileName: fileName,
            normalizedFileName: normalizedSearchKey(fileName)
        )
    }

    private static func normalizedSearchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

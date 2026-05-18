import XCTest
@testable import GitN

final class WorkingTreeFileSearchIndexTests: XCTestCase {
    func testSearchReusesCachedLoaderResultsAcrossQueries() async throws {
        let loader = SearchIndexLoaderProbe(result: [
            "Sources/App/LoginView.swift",
            "Sources/App/SettingsView.swift"
        ])
        let index = WorkingTreeFileSearchIndex(loader: { path in
            try await loader.load(path: path)
        })

        let first = try await index.search(repositoryPath: "/tmp/repo", query: "Login")
        let second = try await index.search(repositoryPath: "/tmp/repo", query: "Settings")

        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(first.matchedFilePaths, ["Sources/App/LoginView.swift"])
        XCTAssertEqual(second.matchedFilePaths, ["Sources/App/SettingsView.swift"])
    }

    func testInvalidateForcesNextSearchToReload() async throws {
        let loader = SearchIndexLoaderProbe(result: [
            "Sources/App/LoginView.swift"
        ])
        let index = WorkingTreeFileSearchIndex(loader: { path in
            try await loader.load(path: path)
        })

        _ = try await index.search(repositoryPath: "/tmp/repo", query: "Login")
        await index.invalidate(repositoryPath: "/tmp/repo")
        _ = try await index.search(repositoryPath: "/tmp/repo", query: "Login")

        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testSearchCanNarrowCandidateFilePathsWithoutLoadingRepositoryIndex() async throws {
        let loader = SearchIndexLoaderProbe(result: [
            "Sources/App/LoginView.swift"
        ])
        let index = WorkingTreeFileSearchIndex(loader: { path in
            try await loader.load(path: path)
        })

        let snapshot = try await index.search(
            repositoryPath: "/path/that/does/not/exist",
            query: "Helper",
            candidateFilePaths: [
                "Sources/Features/Auth/Login.swift",
                "Sources/Other/LoginHelper.swift"
            ]
        )

        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(snapshot.matchedFilePaths, ["Sources/Other/LoginHelper.swift"])
    }
}

private actor SearchIndexLoaderProbe {
    private(set) var callCount = 0
    private let result: [String]

    init(result: [String]) {
        self.result = result
    }

    func load(path: String) throws -> [String] {
        _ = path
        callCount += 1
        return result
    }
}

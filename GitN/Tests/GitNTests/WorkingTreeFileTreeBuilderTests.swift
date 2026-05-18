import XCTest
@testable import GitN

final class WorkingTreeFileTreeBuilderTests: XCTestCase {
    func testBuildExcludesDotGitAndSortsFoldersBeforeFiles() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("src/App.swift", contents: "print(\"app\")\n")
        try repo.writeFile("src/Feature/Feature.swift", contents: "print(\"feature\")\n")
        try repo.writeFile(".env", contents: "TOKEN=1\n")
        try repo.writeFile("README.md", contents: "# Readme\n")

        let builder = WorkingTreeFileTreeBuilder()
        let nodes = try builder.build(at: repo.path)
        let srcNodes = try builder.listDirectory(at: repo.path, relativePath: "src")
        let featureNodes = try builder.listDirectory(at: repo.path, relativePath: "src/Feature")

        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes.map(\.relativePath), ["src", ".env", "README.md"])

        guard case let .folder(name, relativePath) = nodes[0] else {
            return XCTFail("Expected src folder")
        }

        XCTAssertEqual(name, "src")
        XCTAssertEqual(relativePath, "src")
        XCTAssertEqual(srcNodes.map(\.relativePath), ["src/Feature", "src/App.swift"])

        guard case let .folder(featureName, featurePath) = srcNodes[0] else {
            return XCTFail("Expected nested Feature folder")
        }

        XCTAssertEqual(featureName, "Feature")
        XCTAssertEqual(featurePath, "src/Feature")
        XCTAssertEqual(featureNodes.map(\.relativePath), ["src/Feature/Feature.swift"])
        XCTAssertFalse(nodes.contains { $0.relativePath.hasPrefix(".git") })
    }

    func testSearchFindsNestedFilesWithoutExpandedFolders() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/App/Deep/ViewModel.swift", contents: "final class ViewModel {}\n")
        try repo.writeFile("README.md", contents: "# Readme\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "ViewModel")

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["Sources"])
        XCTAssertEqual(snapshot.folderContents["Sources"]?.map(\.relativePath), ["Sources/App"])
        XCTAssertEqual(snapshot.folderContents["Sources/App"]?.map(\.relativePath), ["Sources/App/Deep"])
        XCTAssertEqual(snapshot.folderContents["Sources/App/Deep"]?.map(\.relativePath), ["Sources/App/Deep/ViewModel.swift"])
        XCTAssertEqual(snapshot.expandedFolderPaths, ["Sources", "Sources/App", "Sources/App/Deep"])
    }

    func testTreeSnapshotBuildsAncestorFoldersFromMatchedFilePaths() {
        let snapshot = WorkingTreeFileTreeBuilder().treeSnapshot(
            matchingFilePaths: ["Sources/App/Deep/ViewModel.swift", "README.md"]
        )

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["Sources", "README.md"])
        XCTAssertEqual(snapshot.folderContents["Sources"]?.map(\.relativePath), ["Sources/App"])
        XCTAssertEqual(snapshot.folderContents["Sources/App"]?.map(\.relativePath), ["Sources/App/Deep"])
        XCTAssertEqual(snapshot.folderContents["Sources/App/Deep"]?.map(\.relativePath), ["Sources/App/Deep/ViewModel.swift"])
    }

    func testSearchMatchesFileNamesCaseInsensitively() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/App/SettingsView.swift", contents: "struct SettingsView {}\n")
        try repo.writeFile("Sources/App/SidebarView.swift", contents: "struct SidebarView {}\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "settingsview")

        XCTAssertEqual(snapshot.folderContents["Sources/App"]?.map(\.relativePath), ["Sources/App/SettingsView.swift"])
    }

    func testSearchShowsAncestorFoldersForMatchingDescendants() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("docs/guides/install.md", contents: "Install\n")
        try repo.writeFile("notes.md", contents: "Notes\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "install")

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["docs"])
        XCTAssertEqual(snapshot.folderContents["docs"]?.map(\.relativePath), ["docs/guides"])
        XCTAssertEqual(snapshot.folderContents["docs/guides"]?.map(\.relativePath), ["docs/guides/install.md"])
    }

    func testSearchDoesNotMatchDirectoryNames() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/Features/Auth/Login.swift", contents: "struct Login {}\n")
        try repo.writeFile("Sources/Features/Auth/Session.swift", contents: "struct Session {}\n")
        try repo.writeFile("Sources/Other/FeatureFlag.swift", contents: "struct FeatureFlag {}\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "Features")

        XCTAssertTrue(snapshot.rootNodes.isEmpty)
        XCTAssertTrue(snapshot.folderContents.isEmpty)
    }

    func testSearchIncludesOnlyMatchingFilesWithAncestorFolders() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("Sources/Features/Auth/Login.swift", contents: "struct Login {}\n")
        try repo.writeFile("Sources/Features/Auth/Session.swift", contents: "struct Session {}\n")
        try repo.writeFile("Sources/Other/LoginHelper.swift", contents: "struct LoginHelper {}\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "Login")

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["Sources"])
        XCTAssertEqual(snapshot.folderContents["Sources"]?.map(\.relativePath), ["Sources/Features", "Sources/Other"])
        XCTAssertEqual(snapshot.folderContents["Sources/Features"]?.map(\.relativePath), ["Sources/Features/Auth"])
        XCTAssertEqual(
            snapshot.folderContents["Sources/Features/Auth"]?.map(\.relativePath),
            ["Sources/Features/Auth/Login.swift"]
        )
        XCTAssertEqual(snapshot.folderContents["Sources/Other"]?.map(\.relativePath), ["Sources/Other/LoginHelper.swift"])
        XCTAssertEqual(snapshot.matchedFilePaths, ["Sources/Features/Auth/Login.swift", "Sources/Other/LoginHelper.swift"])
    }

    func testSearchExcludesDotGit() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".git/hooks/search-match", contents: "ignored\n")
        try repo.writeFile("src/search-match.swift", contents: "included\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "search-match")

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["src"])
        XCTAssertEqual(snapshot.folderContents["src"]?.map(\.relativePath), ["src/search-match.swift"])
        XCTAssertFalse(snapshot.folderContents.keys.contains { $0.hasPrefix(".git") })
    }

    func testSearchExcludesGitIgnoredPaths() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile(".gitignore", contents: "build/\n*.log\n")
        try repo.writeFile("build/ignored-match.swift", contents: "ignored\n")
        try repo.writeFile("src/ignored-match.swift", contents: "included\n")
        try repo.writeFile("debug.log", contents: "ignored\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "ignored-match")

        XCTAssertEqual(snapshot.rootNodes.map(\.relativePath), ["src"])
        XCTAssertEqual(snapshot.folderContents["src"]?.map(\.relativePath), ["src/ignored-match.swift"])
        XCTAssertFalse(snapshot.rootNodes.contains { $0.relativePath == "build" })
        XCTAssertFalse(snapshot.rootNodes.contains { $0.relativePath == "debug.log" })
    }

    func testSearchPreservesFolderBeforeFileSortedOrder() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("z-folder/match-file.swift", contents: "z\n")
        try repo.writeFile("a-folder/match-file.swift", contents: "a\n")
        try repo.writeFile("b-match.swift", contents: "b\n")
        try repo.writeFile("a-file-match.swift", contents: "a\n")

        let snapshot = try WorkingTreeFileTreeBuilder().search(at: repo.path, query: "match")

        XCTAssertEqual(
            snapshot.rootNodes.map(\.relativePath),
            ["a-folder", "z-folder", "a-file-match.swift", "b-match.swift"]
        )
    }

    func testSearchSnapshotsProgressByTopLevelDisplayOrder() throws {
        let repo = try TemporaryGitRepository()
        try repo.writeFile("z-folder/match-file.swift", contents: "z\n")
        try repo.writeFile("a-folder/match-file.swift", contents: "a\n")
        try repo.writeFile("match.md", contents: "root\n")

        let snapshots = try WorkingTreeFileTreeBuilder().searchSnapshots(at: repo.path, query: "match")

        XCTAssertEqual(snapshots.map { $0.rootNodes.map(\.relativePath) }, [
            ["a-folder"],
            ["a-folder", "z-folder"],
            ["a-folder", "z-folder", "match.md"]
        ])
    }

    func testIncrementalSearchCanNarrowExistingCandidateFilesWithoutRepositoryScan() async throws {
        let collector = SearchSnapshotCollector()

        try await WorkingTreeFileTreeBuilder().searchIncrementally(
            at: "/path/that/does/not/exist",
            query: "Helper",
            candidateFilePaths: [
                "Sources/Features/Auth/Login.swift",
                "Sources/Other/LoginHelper.swift"
            ]
        ) { snapshot in
            await collector.append(snapshot)
        }

        let snapshots = await collector.snapshots
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].matchedFilePaths, ["Sources/Other/LoginHelper.swift"])
        XCTAssertEqual(snapshots[0].folderContents["Sources/Other"]?.map(\.relativePath), ["Sources/Other/LoginHelper.swift"])
    }
}

private actor SearchSnapshotCollector {
    private var storage: [WorkingTreeFileTreeBuilder.TreeSnapshot] = []

    var snapshots: [WorkingTreeFileTreeBuilder.TreeSnapshot] {
        storage
    }

    func append(_ snapshot: WorkingTreeFileTreeBuilder.TreeSnapshot) {
        storage.append(snapshot)
    }
}

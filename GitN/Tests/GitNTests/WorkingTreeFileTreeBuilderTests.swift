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
}

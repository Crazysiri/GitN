import XCTest
@testable import GitN

final class CodeHostingSupportTests: XCTestCase {
    func testSharedRemoteParserHandlesSSHGitHubURL() {
        XCTAssertEqual(
            CodeHostingRemote.parseRepositoryPath(from: "git@github.com:owner/repo.git"),
            "owner/repo"
        )
    }

    func testSharedRemoteParserHandlesHTTPSGitLabSubgroupURL() {
        XCTAssertEqual(
            CodeHostingRemote.parseRepositoryPath(from: "https://gitlab.example.com/group/subgroup/repo.git"),
            "group/subgroup/repo"
        )
    }

    func testProviderSpecificParsersUseSharedBehavior() {
        let remote = "https://gitlab.example.com/group/repo/"
        XCTAssertEqual(GitHubService.parseRepositoryPath(from: remote), "group/repo")
        XCTAssertEqual(GitLabService.parseProjectPath(from: remote), "group/repo")
    }

    func testCodeHostingProviderDetection() {
        XCTAssertEqual(CodeHostingProvider(remoteURL: "git@github.com:owner/repo.git"), .github)
        XCTAssertEqual(CodeHostingProvider(remoteURL: "https://gitlab.example.com/group/repo.git"), .gitlab)
        XCTAssertEqual(CodeHostingProvider(remoteURL: "ssh://example.com/repo.git"), .unknown)
    }
}

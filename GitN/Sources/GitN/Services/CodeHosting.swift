import Foundation

enum CodeHostingProvider: String, Equatable {
    case gitlab
    case github
    case unknown

    init(remoteURL: String) {
        let normalized = remoteURL.lowercased()
        if normalized.contains("github.com") {
            self = .github
        } else if normalized.contains("gitlab") {
            self = .gitlab
        } else {
            self = .unknown
        }
    }

    var sectionTitle: String {
        switch self {
        case .gitlab: return "MERGE REQUESTS"
        case .github: return "PULL REQUESTS"
        case .unknown: return "CHANGE REQUESTS"
        }
    }

    var singularDisplayName: String {
        switch self {
        case .gitlab: return "Merge Request"
        case .github: return "Pull Request"
        case .unknown: return "Change Request"
        }
    }

    var emptyStateDisplayName: String {
        switch self {
        case .gitlab: return "merge requests"
        case .github: return "pull requests"
        case .unknown: return "change requests"
        }
    }

    var numberPrefix: String {
        switch self {
        case .gitlab: return "!"
        case .github, .unknown: return "#"
        }
    }

    var mergeActionTitle: String? {
        switch self {
        case .gitlab, .github: return "Rebase & Merge"
        case .unknown: return nil
        }
    }
}

enum CodeReviewFilter: String, CaseIterable, Identifiable {
    case opened
    case mine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opened: return "Open"
        case .mine: return "Mine"
        }
    }

    var gitLabState: String { "opened" }

    var gitLabScope: String? {
        switch self {
        case .opened: return nil
        case .mine: return "created_by_me"
        }
    }
}

enum CodeReviewState: Equatable {
    case opened
    case closed
    case merged
}

struct CodeReviewAuthor: Equatable {
    let displayName: String
    let username: String?
    let avatarURL: String?
}

struct CodeReviewItem: Identifiable, Equatable {
    let provider: CodeHostingProvider
    let nativeID: Int
    let number: Int
    let title: String
    let description: String?
    let state: CodeReviewState
    let sourceBranch: String
    let targetBranch: String
    let webURL: String
    let author: CodeReviewAuthor?
    let isDraft: Bool
    let createdAt: String?
    let updatedAt: String?

    var id: String { "\(provider.rawValue)-\(nativeID)" }
    var numberDisplay: String { "\(provider.numberPrefix)\(number)" }
}

actor GitHubService {
    private static let tokenKey = "GitN.githubToken"
    private static let baseURL = "https://api.github.com"

    @MainActor
    static var githubToken: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    @MainActor
    static var isConfigured: Bool {
        !githubToken.isEmpty
    }

    private let repoPath: String
    private let remoteName: String
    private let gitRunner: CodeHostingGitRunner
    private var currentUsernameCache: String?

    init(repoPath: String, remoteName: String = "origin") {
        self.repoPath = repoPath
        self.remoteName = remoteName
        self.gitRunner = CodeHostingGitRunner(repoPath: repoPath)
    }

    private func getConfig() async -> (baseURL: String, token: String)? {
        let token = await Self.githubToken
        guard !token.isEmpty else { return nil }
        return (Self.baseURL, token)
    }

    private func extractRepository() async -> (owner: String, name: String)? {
        let output: String
        do {
            output = try await gitRunner.runOutput(["config", "--get", "remote.\(remoteName).url"])
        } catch {
            return nil
        }

        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = Self.parseRepositoryPath(from: url) else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
    }

    static func parseRepositoryPath(from remoteURL: String) -> String? {
        CodeHostingRemote.parseRepositoryPath(from: remoteURL)
    }

    func listPullRequests(state: CodeReviewFilter = .opened, page: Int = 1, perPage: Int = 50) async throws -> [CodeReviewItem] {
        guard let config = await getConfig() else {
            throw GitHubError.notConfigured
        }
        guard let repo = await extractRepository() else {
            throw GitHubError.cannotDetermineRepository
        }

        let url = "\(config.baseURL)/repos/\(repo.owner)/\(repo.name)/pulls?state=open&page=\(page)&per_page=\(perPage)&sort=updated&direction=desc"
        let data = try await apiRequest(url: url, method: "GET", token: config.token)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var pullRequests = try decoder.decode([GitHubPullRequest].self, from: data)

        if state == .mine {
            let currentUsername = try await currentUsername(baseURL: config.baseURL, token: config.token)
            pullRequests.removeAll { $0.user?.login != currentUsername }
        }

        return pullRequests.map { $0.codeReviewItem }
    }

    func performRebaseAndMerge(prNumber: Int) async throws {
        guard let config = await getConfig() else {
            throw GitHubError.notConfigured
        }
        guard let repo = await extractRepository() else {
            throw GitHubError.cannotDetermineRepository
        }

        let url = "\(config.baseURL)/repos/\(repo.owner)/\(repo.name)/pulls/\(prNumber)/merge"
        let body = try JSONSerialization.data(withJSONObject: ["merge_method": "rebase"])
        _ = try await apiRequest(url: url, method: "PUT", token: config.token, body: body)
    }

    private func currentUsername(baseURL: String, token: String) async throws -> String {
        if let currentUsernameCache {
            return currentUsernameCache
        }

        let data = try await apiRequest(url: "\(baseURL)/user", method: "GET", token: token)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let login = json["login"] as? String,
            !login.isEmpty
        else {
            throw GitHubError.invalidResponse
        }
        currentUsernameCache = login
        return login
    }

    private func apiRequest(url urlString: String, method: String, token: String, body: Data? = nil) async throws -> Data {
        do {
            return try await CodeHostingAPIClient.request(
                url: urlString,
                method: method,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "Content-Type": body == nil ? "" : "application/json",
                ].filter { !$0.value.isEmpty },
                body: body
            )
        } catch let error as CodeHostingSupportError {
            throw GitHubError(error)
        } catch {
            throw GitHubError.networkError(error.localizedDescription)
        }
    }
}

enum GitHubError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case cannotDetermineRepository
    case invalidResponse
    case networkError(String)
    case apiError(Int, String)
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GitHub not configured. Set token in Settings -> Git."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .cannotDetermineRepository:
            return "Cannot determine GitHub repository from the selected remote URL."
        case .invalidResponse:
            return "GitHub API returned an unexpected response."
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let code, let body):
            return "GitHub API error (\(code)): \(body)"
        case .gitFailed(let message):
            return message
        }
    }
}

private extension GitHubError {
    init(_ error: CodeHostingSupportError) {
        switch error {
        case .invalidURL(let url):
            self = .invalidURL(url)
        case .invalidResponse:
            self = .networkError("Invalid response")
        case .networkError(let message):
            self = .networkError(message)
        case .apiError(let code, let body):
            self = .apiError(code, body)
        case .gitFailed(let message):
            self = .gitFailed(message)
        }
    }
}

private struct GitHubPullRequest: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let draft: Bool?
    let htmlUrl: String
    let createdAt: String?
    let updatedAt: String?
    let user: GitHubUser?
    let head: GitHubBranchRef
    let base: GitHubBranchRef

    var codeReviewItem: CodeReviewItem {
        CodeReviewItem(
            provider: .github,
            nativeID: id,
            number: number,
            title: title,
            description: body,
            state: state == "closed" ? .closed : .opened,
            sourceBranch: head.ref,
            targetBranch: base.ref,
            webURL: htmlUrl,
            author: user.map {
                CodeReviewAuthor(displayName: $0.login, username: $0.login, avatarURL: $0.avatarUrl)
            },
            isDraft: draft ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct GitHubBranchRef: Codable {
    let ref: String
}

private struct GitHubUser: Codable {
    let login: String
    let avatarUrl: String?
}

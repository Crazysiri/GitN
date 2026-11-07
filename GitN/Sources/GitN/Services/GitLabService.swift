import Foundation

// MARK: - GitLab API Service

actor GitLabService {
    
    // MARK: - Settings Keys
    
    private static let urlKey = "GitN.gitlabURL"
    private static let projectIDCacheKey = "GitN.gitlabProjectIDCache" // [cacheKey: projectID]
    
    // MARK: - Settings (thread-safe via MainActor for UI reads)
    
    @MainActor
    static var gitlabURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }
    
    @MainActor
    static var gitlabToken: String {
        HostedCredentialStore.shared.token(for: .gitlab)
    }
    
    @MainActor
    static func saveToken(_ value: String) throws {
        try HostedCredentialStore.shared.save(value, for: .gitlab)
    }

    @MainActor
    static var isConfigured: Bool {
        !gitlabURL.isEmpty && !gitlabToken.isEmpty
    }

    static var configuredHost: String? {
        let configuredURL = UserDefaults.standard.string(forKey: urlKey) ?? ""
        return CodeHostingRemote.parseHost(from: configuredURL)
    }
    
    // MARK: - Project ID Cache
    
    private static func cachedProjectID(for cacheKey: String) -> Int? {
        guard let dict = UserDefaults.standard.dictionary(forKey: projectIDCacheKey) as? [String: Int] else { return nil }
        return dict[cacheKey]
    }
    
    private static func cacheProjectID(_ projectID: Int, for cacheKey: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: projectIDCacheKey) as? [String: Int]) ?? [:]
        dict[cacheKey] = projectID
        UserDefaults.standard.set(dict, forKey: projectIDCacheKey)
    }

    private static func projectIDCacheKey(repoPath: String, remoteURL: String, baseURL: String) -> String {
        let normalizedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.resolvingSymlinksInPath().path
        let normalizedRemoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedRepoPath)|\(baseURL)|\(normalizedRemoteURL)"
    }
    
    // MARK: - Instance
    
    private let repoPath: String
    private let remoteName: String
    private let gitRunner: CodeHostingGitRunner
    
    init(repoPath: String, remoteName: String = "origin") {
        self.repoPath = repoPath
        self.remoteName = remoteName
        self.gitRunner = CodeHostingGitRunner(repoPath: repoPath)
    }
    
    // MARK: - Get Base URL & Token
    
    private func getConfig() async -> (baseURL: String, token: String)? {
        let url = await Self.gitlabURL
        let token = await Self.gitlabToken
        guard !url.isEmpty, !token.isEmpty else { return nil }
        // Trim trailing slash
        let base = url.hasSuffix("/") ? String(url.dropLast()) : url
        return (base, token)
    }
    
    // MARK: - Extract project path from remote origin URL

    private func extractRemoteURL() async -> String? {
        let output: String
        do {
            output = try await runGitOutput(["config", "--get", "remote.\(remoteName).url"])
        } catch {
            return nil
        }

        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
    
    /// Extracts the project path (e.g. "group/project") from a remote origin URL.
    /// Supports SSH (git@host:group/project.git) and HTTPS (https://host/group/project.git) formats.
    func extractProjectPath() async -> String? {
        guard let url = await extractRemoteURL() else { return nil }
        return Self.parseProjectPath(from: url)
    }
    
    static func parseProjectPath(from remoteURL: String) -> String? {
        CodeHostingRemote.parseRepositoryPath(from: remoteURL)
    }
    
    // MARK: - Resolve Project ID
    
    /// Get or fetch the GitLab project ID. Caches the result.
    func resolveProjectID() async throws -> Int {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        guard let remoteURL = await extractRemoteURL() else {
            throw GitLabError.cannotDetermineProject
        }

        let cacheKey = Self.projectIDCacheKey(repoPath: repoPath, remoteURL: remoteURL, baseURL: config.baseURL)
        if let cached = Self.cachedProjectID(for: cacheKey) {
            return cached
        }
        
        guard let projectPath = Self.parseProjectPath(from: remoteURL) else {
            throw GitLabError.cannotDetermineProject
        }
        
        // URL-encode the project path (group/project → group%2Fproject)
        guard let encoded = projectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") else {
            throw GitLabError.cannotDetermineProject
        }
        
        let url = "\(config.baseURL)/api/v4/projects/\(encoded)"
        let data = try await apiRequest(url: url, method: "GET", token: config.token)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectID = json["id"] as? Int else {
            throw GitLabError.projectNotFound(projectPath)
        }
        
        Self.cacheProjectID(projectID, for: cacheKey)
        return projectID
    }
    
    // MARK: - List Merge Requests
    
    func listMergeRequests(state: CodeReviewFilter = .opened, page: Int = 1, perPage: Int = 50) async throws -> [CodeReviewItem] {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        let projectID = try await resolveProjectID()
        
        var urlStr = "\(config.baseURL)/api/v4/projects/\(projectID)/merge_requests"
        urlStr += "?state=\(state.gitLabState)&page=\(page)&per_page=\(perPage)&order_by=updated_at&sort=desc"
        if let scope = state.gitLabScope {
            urlStr += "&scope=\(scope)"
        }
        
        let data = try await apiRequest(url: urlStr, method: "GET", token: config.token)
        
        return try Self.decodeMRList(data).map(\.codeReviewItem)
    }
    
    private static func decodeMRList(_ data: Data) throws -> [GitLabMR] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GitLabMR].self, from: data)
    }
    
    // MARK: - Merge a MR (with rebase)
    
    /// Accepts (merges) a merge request via the GitLab API.
    func acceptMergeRequest(mrIID: Int) async throws {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        let projectID = try await resolveProjectID()
        let urlStr = "\(config.baseURL)/api/v4/projects/\(projectID)/merge_requests/\(mrIID)/merge"
        
        let _ = try await apiRequest(url: urlStr, method: "PUT", token: config.token)
    }
    
    /// Rebase the source branch of a merge request using the GitLab API.
    func rebaseMergeRequest(mrIID: Int) async throws {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        let projectID = try await resolveProjectID()
        let urlStr = "\(config.baseURL)/api/v4/projects/\(projectID)/merge_requests/\(mrIID)/rebase"
        
        let _ = try await apiRequest(url: urlStr, method: "PUT", token: config.token)
    }
    
    /// Get a single MR's details (to check rebase status, etc.)
    func getMergeRequest(mrIID: Int) async throws -> GitLabMR {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        let projectID = try await resolveProjectID()
        let urlStr = "\(config.baseURL)/api/v4/projects/\(projectID)/merge_requests/\(mrIID)"
        
        let data = try await apiRequest(url: urlStr, method: "GET", token: config.token)
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(GitLabMR.self, from: data)
    }
    
    // MARK: - Local rebase source branch then merge via API
    
    /// Full merge flow:
    /// 1. Stash current working directory
    /// 2. Checkout source branch
    /// 3. Rebase onto target branch
    /// 4. Push rebased source branch
    /// 5. Call API to merge
    /// 6. Restore original branch & pop stash
    /// On failure at any point, attempt to restore previous state.
    func performRebaseAndMerge(mrIID: Int, sourceBranch: String, targetBranch: String) async throws {
        // Save current state
        let originalBranch = try await runGitOutput(["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasChanges = try await hasWorkingDirectoryChanges()
        
        // Step 1: Stash if needed
        if hasChanges {
            try await runGit(["stash", "save", "GitN: auto-stash before MR rebase"])
        }
        
        // Helper: restore original branch and stash
        func restore() async {
            if originalBranch != sourceBranch {
                try? await runGit(["checkout", originalBranch])
            }
            if hasChanges { try? await runGit(["stash", "pop"]) }
        }
        
        do {
            // Step 2: Fetch latest
            try await runGit(["fetch", remoteName])
            
            // Step 3: Checkout source branch
            // Check if we're already on the source branch
            let currentBranch = try await runGitOutput(["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if currentBranch != sourceBranch {
                // Check if local branch exists
                let branchExists = (try? await runGitOutput(["rev-parse", "--verify", sourceBranch])) != nil
                if branchExists {
                    try await runGit(["checkout", sourceBranch])
                } else {
                    // Create local tracking branch from origin
                    try await runGit(["checkout", "-b", sourceBranch, "\(remoteName)/\(sourceBranch)"])
                }
            }
            
            // Step 4: Refuse to rewrite a local source branch that contains unpushed commits.
            if try await localBranchHasUnpushedCommits(sourceBranch: sourceBranch) {
                await restore()
                throw GitLabError.localSourceBranchAhead(sourceBranch)
            }
            
            // Step 5: Rebase onto target
            do {
                try await runGit(["rebase", "\(remoteName)/\(targetBranch)"])
            } catch {
                // Rebase failed, abort and restore
                try? await runGit(["rebase", "--abort"])
                await restore()
                throw GitLabError.rebaseFailed(sourceBranch, targetBranch, error.localizedDescription)
            }
            
            // Step 6: Force push the rebased source branch
            try await runGit(["push", remoteName, sourceBranch, "--force-with-lease"])
            
            // Step 7: Wait for GitLab to process the push, then call API to merge (with retry)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            
            let maxRetries = 2
            var lastMergeError: Error?
            for attempt in 0...maxRetries {
                do {
                    try await acceptMergeRequest(mrIID: mrIID)
                    lastMergeError = nil
                    break
                } catch {
                    lastMergeError = error
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                    }
                }
            }
            if let mergeError = lastMergeError {
                await restore()
                throw GitLabError.mergeFailed(mergeError.localizedDescription)
            }
            
            // Step 8: Restore original branch & stash
            await restore()
            
        } catch let error as GitLabError {
            throw error
        } catch {
            // Generic failure, restore
            await restore()
            throw error
        }
    }
    
    // MARK: - Helpers
    
    private func hasWorkingDirectoryChanges() async throws -> Bool {
        let output = try await runGitOutput(["status", "--porcelain"])
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func localBranchHasUnpushedCommits(sourceBranch: String) async throws -> Bool {
        let output = try await runGitOutput(["rev-list", "--count", "\(remoteName)/\(sourceBranch)..\(sourceBranch)"])
        return (Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
    }
    
    private func apiRequest(url urlStr: String, method: String, token: String, body: Data? = nil) async throws -> Data {
        do {
            return try await CodeHostingAPIClient.request(
                url: urlStr,
                method: method,
                headers: [
                    "PRIVATE-TOKEN": token,
                    "Content-Type": "application/json",
                ],
                body: body
            )
        } catch let error as CodeHostingSupportError {
            throw GitLabError(error)
        } catch {
            throw GitLabError.networkError(error.localizedDescription)
        }
    }
    
    private func runGit(_ args: [String]) async throws {
        do {
            try await gitRunner.run(args)
        } catch let error as CodeHostingSupportError {
            throw GitLabError(error)
        } catch {
            throw GitLabError.networkError(error.localizedDescription)
        }
    }
    
    private func runGitOutput(_ args: [String]) async throws -> String {
        do {
            return try await gitRunner.runOutput(args)
        } catch let error as CodeHostingSupportError {
            throw GitLabError(error)
        } catch {
            throw GitLabError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - Error

enum GitLabError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case cannotDetermineProject
    case projectNotFound(String)
    case networkError(String)
    case apiError(Int, String)
    case localSourceBranchAhead(String)
    case rebaseFailed(String, String, String)
    case mergeFailed(String)
    case gitFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GitLab not configured. Set URL and token in Settings -> Git."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .cannotDetermineProject:
            return "Cannot determine GitLab project from remote origin URL."
        case .projectNotFound(let path):
            return "Project '\(path)' not found on GitLab."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let body):
            return "GitLab API error (\(code)): \(body)"
        case .localSourceBranchAhead(let branch):
            return "Local branch '\(branch)' has unpushed commits. Push or move them before using Rebase & Merge."
        case .rebaseFailed(let source, let target, let detail):
            return "Rebase '\(source)' onto '\(target)' failed: \(detail)"
        case .mergeFailed(let detail):
            return "Merge failed: \(detail)"
        case .gitFailed(let msg):
            return msg
        }
    }
}

private extension GitLabError {
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

// MARK: - MR State Filter

// MARK: - GitLab MR Model

struct GitLabMR: Identifiable, Equatable {
    let id: Int
    let iid: Int
    let title: String
    let description: String?
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let webUrl: String
    let author: GitLabUser?
    let mergeStatus: String?
    let hasConflicts: Bool?
    let draft: Bool?
    let createdAt: String?
    let updatedAt: String?
    
    var stateEnum: MRState {
        switch state {
        case "opened": return .opened
        case "closed": return .closed
        case "merged": return .merged
        default: return .opened
        }
    }
    
    var isDraft: Bool { draft ?? false }

    var codeReviewItem: CodeReviewItem {
        CodeReviewItem(
            provider: .gitlab,
            nativeID: id,
            number: iid,
            title: title,
            description: description,
            state: CodeReviewState(stateEnum),
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            webURL: webUrl,
            author: author.map {
                CodeReviewAuthor(displayName: $0.name, username: $0.username, avatarURL: $0.avatarUrl)
            },
            isDraft: isDraft,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    enum MRState {
        case opened, closed, merged
    }
}

extension CodeReviewState {
    init(_ state: GitLabMR.MRState) {
        switch state {
        case .opened: self = .opened
        case .closed: self = .closed
        case .merged: self = .merged
        }
    }
}

extension GitLabMR: Codable {
    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state
        case sourceBranch, targetBranch, webUrl
        case author, mergeStatus, hasConflicts, draft
        case createdAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        iid = try c.decode(Int.self, forKey: .iid)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        state = try c.decode(String.self, forKey: .state)
        sourceBranch = try c.decode(String.self, forKey: .sourceBranch)
        targetBranch = try c.decode(String.self, forKey: .targetBranch)
        webUrl = try c.decode(String.self, forKey: .webUrl)
        author = try c.decodeIfPresent(GitLabUser.self, forKey: .author)
        mergeStatus = try c.decodeIfPresent(String.self, forKey: .mergeStatus)
        hasConflicts = try c.decodeIfPresent(Bool.self, forKey: .hasConflicts)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct GitLabUser: Codable, Equatable {
    let id: Int
    let name: String
    let username: String
    let avatarUrl: String?
}

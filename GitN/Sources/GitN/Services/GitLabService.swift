import Foundation

// MARK: - GitLab API Service

actor GitLabService {
    
    // MARK: - Settings Keys
    
    private static let urlKey = "GitN.gitlabURL"
    private static let tokenKey = "GitN.gitlabToken"
    private static let projectIDCacheKey = "GitN.gitlabProjectIDCache" // [repoPath: projectID]
    
    // MARK: - Settings (thread-safe via MainActor for UI reads)
    
    @MainActor
    static var gitlabURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }
    
    @MainActor
    static var gitlabToken: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    
    @MainActor
    static var isConfigured: Bool {
        !gitlabURL.isEmpty && !gitlabToken.isEmpty
    }
    
    // MARK: - Project ID Cache
    
    private static func cachedProjectID(for repoPath: String) -> Int? {
        guard let dict = UserDefaults.standard.dictionary(forKey: projectIDCacheKey) as? [String: Int] else { return nil }
        return dict[repoPath]
    }
    
    private static func cacheProjectID(_ projectID: Int, for repoPath: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: projectIDCacheKey) as? [String: Int]) ?? [:]
        dict[repoPath] = projectID
        UserDefaults.standard.set(dict, forKey: projectIDCacheKey)
    }
    
    // MARK: - Instance
    
    private let repoPath: String
    
    init(repoPath: String) {
        self.repoPath = repoPath
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
    
    /// Extracts the project path (e.g. "group/project") from a remote origin URL.
    /// Supports SSH (git@host:group/project.git) and HTTPS (https://host/group/project.git) formats.
    func extractProjectPath() async -> String? {
        let output: String
        do {
            output = try await runGitOutput(["config", "--get", "remote.origin.url"])
        } catch {
            return nil
        }
        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return Self.parseProjectPath(from: url)
    }
    
    static func parseProjectPath(from remoteURL: String) -> String? {
        var path: String
        
        if remoteURL.contains("@") && remoteURL.contains(":") {
            // SSH format: git@gitlab.example.com:group/subgroup/project.git
            guard let colonIdx = remoteURL.firstIndex(of: ":") else { return nil }
            path = String(remoteURL[remoteURL.index(after: colonIdx)...])
        } else if remoteURL.hasPrefix("http://") || remoteURL.hasPrefix("https://") {
            // HTTPS format: https://gitlab.example.com/group/subgroup/project.git
            guard let urlObj = URL(string: remoteURL) else { return nil }
            // path is "/group/subgroup/project.git"
            path = urlObj.path
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        } else {
            return nil
        }
        
        // Remove .git suffix
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        // Remove trailing slash
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        
        return path.isEmpty ? nil : path
    }
    
    // MARK: - Resolve Project ID
    
    /// Get or fetch the GitLab project ID. Caches the result.
    func resolveProjectID() async throws -> Int {
        // Check cache first
        if let cached = Self.cachedProjectID(for: repoPath) {
            return cached
        }
        
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        guard let projectPath = await extractProjectPath() else {
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
        
        Self.cacheProjectID(projectID, for: repoPath)
        return projectID
    }
    
    // MARK: - List Merge Requests
    
    func listMergeRequests(state: MRStateFilter = .opened, page: Int = 1, perPage: Int = 50) async throws -> [GitLabMR] {
        guard let config = await getConfig() else {
            throw GitLabError.notConfigured
        }
        
        let projectID = try await resolveProjectID()
        
        var urlStr = "\(config.baseURL)/api/v4/projects/\(projectID)/merge_requests"
        urlStr += "?state=\(state.apiState)&page=\(page)&per_page=\(perPage)&order_by=updated_at&sort=desc"
        if let scope = state.apiScope {
            urlStr += "&scope=\(scope)"
        }
        
        let data = try await apiRequest(url: urlStr, method: "GET", token: config.token)
        
        return try Self.decodeMRList(data)
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
        
        do {
            // Step 2: Fetch latest
            try await runGit(["fetch", "origin"])
            
            // Step 3: Checkout source branch
            try await runGit(["checkout", sourceBranch])
            
            // Step 4: Rebase onto target
            do {
                try await runGit(["rebase", "origin/\(targetBranch)"])
            } catch {
                // Rebase failed, abort and restore
                try? await runGit(["rebase", "--abort"])
                try? await runGit(["checkout", originalBranch])
                if hasChanges { try? await runGit(["stash", "pop"]) }
                throw GitLabError.rebaseFailed(sourceBranch, targetBranch, error.localizedDescription)
            }
            
            // Step 5: Force push the rebased source branch
            try await runGit(["push", "origin", sourceBranch, "--force-with-lease"])
            
            // Step 6: Call API to merge
            do {
                try await acceptMergeRequest(mrIID: mrIID)
            } catch {
                // API merge failed, restore
                try? await runGit(["checkout", originalBranch])
                if hasChanges { try? await runGit(["stash", "pop"]) }
                throw GitLabError.mergeFailed(error.localizedDescription)
            }
            
            // Step 7: Restore original branch
            try? await runGit(["checkout", originalBranch])
            if hasChanges { try? await runGit(["stash", "pop"]) }
            
        } catch let error as GitLabError {
            throw error
        } catch {
            // Generic failure, restore
            try? await runGit(["checkout", originalBranch])
            if hasChanges { try? await runGit(["stash", "pop"]) }
            throw error
        }
    }
    
    // MARK: - Helpers
    
    private func hasWorkingDirectoryChanges() async throws -> Bool {
        let output = try await runGitOutput(["status", "--porcelain"])
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func apiRequest(url urlStr: String, method: String, token: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: urlStr) else {
            throw GitLabError.invalidURL(urlStr)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = body }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabError.networkError("Invalid response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitLabError.apiError(httpResponse.statusCode, body)
        }
        
        return data
    }
    
    // MARK: - Git CLI helpers (same pattern as GitService)
    
    private func runGit(_ args: [String]) async throws {
        let path = repoPath
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: path)
                let pipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    let _ = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    if proc.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                        continuation.resume(throwing: GitLabError.gitFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func runGitOutput(_ args: [String]) async throws -> String {
        let path = repoPath
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: path)
                let pipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    if proc.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                        continuation.resume(throwing: GitLabError.gitFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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
    case rebaseFailed(String, String, String)
    case mergeFailed(String)
    case gitFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GitLab not configured. Set URL and token in Settings → GitLab."
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
        case .rebaseFailed(let source, let target, let detail):
            return "Rebase '\(source)' onto '\(target)' failed: \(detail)"
        case .mergeFailed(let detail):
            return "Merge failed: \(detail)"
        case .gitFailed(let msg):
            return msg
        }
    }
}

// MARK: - MR State Filter

enum MRStateFilter: String, CaseIterable, Identifiable {
    case opened
    case mine
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .opened: return "Open"
        case .mine: return "My MRs"
        }
    }
    
    var icon: String {
        switch self {
        case .opened: return "arrow.triangle.pull"
        case .mine: return "person.circle"
        }
    }
    
    /// GitLab API state parameter value
    var apiState: String {
        return "opened"
    }
    
    /// GitLab API scope parameter value (nil means no scope filter)
    var apiScope: String? {
        switch self {
        case .opened: return nil
        case .mine: return "created_by_me"
        }
    }
}

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
    
    enum MRState {
        case opened, closed, merged
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

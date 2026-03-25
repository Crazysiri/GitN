import SwiftUI
import Combine
import Clibgit2

private func withLibgit2<T>(_ body: () -> T) -> T {
    git_libgit2_init()
    defer { git_libgit2_shutdown() }
    return body()
}

@Observable
final class AppModel {
    var tabs: [RepoTab] = []
    var selectedTabID: UUID?
    var showNewTab: Bool = true
    var pendingGitInit: (path: String, name: String)?

    private static let savedReposKey = "GitN.savedRepos"
    private static let recentReposKey = "GitN.recentRepos"

    var selectedTab: RepoTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var recentRepos: [SavedRepo] = []

    init() {
        restoreSavedRepos()
        restoreRecentRepos()
        // 如果有已保存的仓库，默认不显示 NewTab
        if !tabs.isEmpty {
            showNewTab = false
        }
    }

    func openRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        openRepository(path: url.path, name: url.lastPathComponent)
    }

    func openRepository(path: String, name: String) {
        guard let resolved = resolveRepositorySelection(path: path, fallbackName: name) else {
            pendingGitInit = (path: normalizedPath(path), name: name)
            return
        }

        _addTab(path: resolved.path, name: resolved.name)
    }

    func initAndOpenRepository(path: String, name: String) {
        let normalized = normalizedPath(path)
        let didInit = withLibgit2 {
            var repo: OpaquePointer?
            defer {
                if let repo { git_repository_free(repo) }
            }
            guard git_repository_init(&repo, normalized, 0) == 0, let repo else {
                return false
            }
            return bootstrapInitialRepositoryState(repo: repo, workingDirectory: normalized)
        }

        guard didInit else { return }
        _addTab(path: normalized, name: name)
    }

    func cloneRepository(urlString: String, destinationPath: String, name: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["clone", urlString, destinationPath]

            let pipe = Pipe()
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clone failed"
                throw GitError.operationFailed(errMsg)
            }
        }.value

        _addTab(path: destinationPath, name: name)
    }

    private func _addTab(path: String, name: String) {
        // 检查是否已存在
        if let existing = tabs.first(where: { $0.path == path }) {
            selectedTabID = existing.id
            showNewTab = false
            addToRecent(path: path, name: name)
            return
        }

        // 不存在则创建新 tab
        let tab = RepoTab(path: path, name: name)
        tabs.append(tab)
        selectedTabID = tab.id
        showNewTab = false
        addToRecent(path: path, name: name)
        persistRepos()
    }
    
    func showNewTabView() {
        showNewTab = true
        selectedTabID = nil
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            if tabs.isEmpty {
                showNewTab = true
                selectedTabID = nil
            } else {
                selectedTabID = tabs.first?.id
            }
        }
        persistRepos()
    }

    func addTab(path: String, name: String) {
        _addTab(path: path, name: name)
    }

    // MARK: - Recent Repos Management

    func removeFromRecent(path: String) {
        recentRepos.removeAll { $0.path == path }
        persistRecentRepos()
    }

    private func addToRecent(path: String, name: String) {
        let repo = SavedRepo(path: path, name: name)
        
        // 移除已存在的相同路径
        recentRepos.removeAll { $0.path == path }
        
        // 添加到最前面
        recentRepos.insert(repo, at: 0)
        
        // 限制为最近15条
        if recentRepos.count > 15 {
            recentRepos = Array(recentRepos.prefix(15))
        }
        
        persistRecentRepos()
    }

    private func persistRecentRepos() {
        if let data = try? JSONEncoder().encode(recentRepos) {
            UserDefaults.standard.set(data, forKey: Self.recentReposKey)
        }
    }

    private func restoreRecentRepos() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentReposKey),
              let saved = try? JSONDecoder().decode([SavedRepo].self, from: data)
        else { return }
        
        // 去重：保留第一次出现的路径
        var seenPaths: Set<String> = []
        recentRepos = saved.filter { repo in
            if seenPaths.contains(repo.path) {
                return false
            }
            seenPaths.insert(repo.path)
            return true
        }
        
        // 限制为15条
        if recentRepos.count > 15 {
            recentRepos = Array(recentRepos.prefix(15))
        }
    }

    // MARK: - Persistence

    private func persistRepos() {
        let saved = tabs.map { SavedRepo(path: $0.path, name: $0.name) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedReposKey)
        }
    }

    private func restoreSavedRepos() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedReposKey),
              let saved = try? JSONDecoder().decode([SavedRepo].self, from: data),
              !saved.isEmpty
        else { return }

        for repo in saved {
            let tab = RepoTab(path: repo.path, name: repo.name)
            tabs.append(tab)
        }
        selectedTabID = tabs.first?.id
    }

    private func resolveRepositorySelection(path: String, fallbackName: String) -> (path: String, name: String)? {
        let normalized = normalizedPath(path)

        return withLibgit2 {
            var repo: OpaquePointer?
            defer {
                if let repo { git_repository_free(repo) }
            }

            guard git_repository_open_ext(&repo, normalized, 0, nil) == 0, let repo else {
                return nil
            }

            let repoPath = resolvedRepositoryPath(from: repo, fallback: normalized)
            let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
            return (repoPath, repoName.isEmpty ? fallbackName : repoName)
        }
    }

    private func resolvedRepositoryPath(from repo: OpaquePointer, fallback: String) -> String {
        if git_repository_is_bare(repo) == 0, let workdir = git_repository_workdir(repo) {
            return normalizedPath(String(cString: workdir))
        }

        if let gitDir = git_repository_path(repo) {
            let url = URL(fileURLWithPath: String(cString: gitDir)).deletingLastPathComponent()
            return normalizedPath(url.path)
        }

        return fallback
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func bootstrapInitialRepositoryState(repo: OpaquePointer, workingDirectory: String) -> Bool {
        guard repositoryHasNoLocalBranches(repo) else { return true }
        guard git_repository_set_head(repo, "refs/heads/master") == 0 else { return false }

        let readmePath = (workingDirectory as NSString).appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: readmePath) {
            let content = "# \(URL(fileURLWithPath: workingDirectory).lastPathComponent)\n"
            do {
                try content.write(toFile: readmePath, atomically: true, encoding: .utf8)
            } catch {
                return false
            }
        }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else { return false }
        defer { git_index_free(index) }

        guard git_index_add_bypath(index, "README.md") == 0 else { return false }
        guard git_index_write(index) == 0 else { return false }

        var treeOid = git_oid()
        guard git_index_write_tree(&treeOid, index) == 0 else { return false }

        var tree: OpaquePointer?
        guard git_tree_lookup(&tree, repo, &treeOid) == 0, let tree else { return false }
        defer { git_tree_free(tree) }

        guard let sig = createInitialCommitSignature(repo: repo) else { return false }
        defer { git_signature_free(sig) }

        var commitOid = git_oid()
        return git_commit_create(
            &commitOid,
            repo,
            "HEAD",
            sig,
            sig,
            nil,
            "Initial commit",
            tree,
            0,
            nil
        ) == 0
    }

    private func repositoryHasNoLocalBranches(_ repo: OpaquePointer) -> Bool {
        var iterator: OpaquePointer?
        guard git_branch_iterator_new(&iterator, repo, GIT_BRANCH_LOCAL) == 0, let iterator else {
            return true
        }
        defer { git_branch_iterator_free(iterator) }

        var reference: OpaquePointer?
        var branchType = git_branch_t(rawValue: 0)
        let rc = git_branch_next(&reference, &branchType, iterator)
        if let reference { git_reference_free(reference) }
        return rc != 0
    }

    private func createInitialCommitSignature(repo: OpaquePointer) -> UnsafeMutablePointer<git_signature>? {
        var sig: UnsafeMutablePointer<git_signature>?
        if git_signature_default(&sig, repo) == 0 {
            return sig
        }

        let name = NSFullUserName().isEmpty ? "GitN User" : NSFullUserName()
        let email = "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
        if git_signature_now(&sig, name, email) == 0 {
            return sig
        }
        return nil
    }
}

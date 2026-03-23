import SwiftUI
import Combine
import Clibgit2

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
        // 检查是否是 git 仓库
        var repo: OpaquePointer?
        let isGitRepo = git_repository_open_ext(&repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil) == 0
        if let repo { git_repository_free(repo) }

        if !isGitRepo {
            pendingGitInit = (path: path, name: name)
            return
        }

        _addTab(path: path, name: name)
    }

    func initAndOpenRepository(path: String, name: String) {
        var repo: OpaquePointer?
        guard git_repository_init(&repo, path, 0) == 0 else { return }
        if let repo { git_repository_free(repo) }
        _addTab(path: path, name: name)
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
}
